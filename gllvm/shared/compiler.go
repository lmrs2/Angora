//
// OCCAM
//
// Copyright (c) 2017, SRI International
//
//  All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// * Neither the name of SRI International nor the names of its contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

package shared

import (
	"io"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

type bitcodeToObjectLink struct {
	bcPath  string
	objPath string
}

//Compile wraps a call to the compiler with the given args.
func Compile(args []string, compiler string) (exitCode int) {
	exitCode = 0
	//in the configureOnly case we have to know the exit code of the compile
	//because that is how configure figures out what it can and cannot do.

	ok := true

	compilerExecName := GetCompilerExecName(compiler)

	pr := parse(args)

	var wg sync.WaitGroup

	// If configure only or print only are set, just execute the compiler
	if skipBitcodeGeneration(pr) {
		wg.Add(1)
		go execCompile(compilerExecName, pr, &wg, &ok)
		wg.Wait()

		if !ok {
			exitCode = 1
		}

		// Else try to build bitcode as well
	} else {
		var bcObjLinks []bitcodeToObjectLink
		var newObjectFiles []string

		wg.Add(2)
		go execCompile(compilerExecName, pr, &wg, &ok)
		go buildAndAttachBitcode(compilerExecName, pr, &bcObjLinks, &newObjectFiles, &wg)
		wg.Wait()

		//grok the exit code
		if !ok {
			exitCode = 1
		} else {
			// When objects and bitcode are built we can attach bitcode paths
			// to object files and link
			for _, link := range bcObjLinks {
				attachBitcodePathToObject(link.bcPath, link.objPath)
			}
			if !pr.IsCompileOnly {
				compileTimeLinkFiles(compilerExecName, pr, newObjectFiles)
			}
		}
	}
	return
}

// Compiles bitcode files and mutates the list of bc->obj links to perform + the list of
// new object files to link
func buildAndAttachBitcode(compilerExecName string, pr parserResult, bcObjLinks *[]bitcodeToObjectLink, newObjectFiles *[]string, wg *sync.WaitGroup) {
	defer (*wg).Done()

	var hidden = !pr.IsCompileOnly

	if len(pr.InputFiles) == 1 && pr.IsCompileOnly {
		var srcFile = pr.InputFiles[0]
		objFile, bcFile := getArtifactNames(pr, 0, hidden)
		buildBitcodeFile(compilerExecName, pr, srcFile, bcFile)
		*bcObjLinks = append(*bcObjLinks, bitcodeToObjectLink{bcPath: bcFile, objPath: objFile})
	} else {
		for i, srcFile := range pr.InputFiles {
			objFile, bcFile := getArtifactNames(pr, i, hidden)
			if hidden {
				buildObjectFile(compilerExecName, pr, srcFile, objFile)
				*newObjectFiles = append(*newObjectFiles, objFile)
			}
			if strings.HasSuffix(srcFile, ".bc") {
				*bcObjLinks = append(*bcObjLinks, bitcodeToObjectLink{bcPath: srcFile, objPath: objFile})
			} else {
				buildBitcodeFile(compilerExecName, pr, srcFile, bcFile)
				*bcObjLinks = append(*bcObjLinks, bitcodeToObjectLink{bcPath: bcFile, objPath: objFile})
			}
		}
	}
}

func attachBitcodePathToObject(bcFile, objFile string) {
	// We can only attach a bitcode path to certain file types
	switch filepath.Ext(objFile) {
	case
		".o",
		".lo",
		".os",
		".So",
		".po":
		// Store bitcode path to temp file
		var absBcPath, _ = filepath.Abs(bcFile)
		tmpContent := []byte(absBcPath + "\n")
		tmpFile, err := ioutil.TempFile("", "gllvm")
		if err != nil {
			LogError("attachBitcodePathToObject: %v\n", err)
			// was LogFatal
			return
		}
		defer CheckDefer(func() error { return os.Remove(tmpFile.Name()) })
		if _, err := tmpFile.Write(tmpContent); err != nil {
			LogError("attachBitcodePathToObject: %v\n", err)
			// was LogFatal
			return
		}
		if err := tmpFile.Close(); err != nil {
			LogError("attachBitcodePathToObject: %v\n", err)
			// was LogFatal
			return
		}

		// Let's write the bitcode section
		var attachCmd string
		var attachCmdArgs []string
		if runtime.GOOS == osDARWIN {
			attachCmd = "ld"
			attachCmdArgs = []string{"-r", "-keep_private_externs", objFile, "-sectcreate", DarwinSegmentName, DarwinSectionName, tmpFile.Name(), "-o", objFile}
		} else {
			attachCmd = "objcopy"
			attachCmdArgs = []string{"--add-section", ELFSectionName + "=" + tmpFile.Name(), objFile}
		}

		// Run the attach command and ignore errors
		_, nerr := execCmd(attachCmd, attachCmdArgs, "")
		if nerr != nil {
			LogDebug("%v %v failed because %v\n", attachCmd, attachCmdArgs, nerr)
		}

		// Copy bitcode file to store, if necessary
		if bcStorePath := LLVMBitcodeStorePath; bcStorePath != "" {
			destFilePath := path.Join(bcStorePath, getHashedPath(absBcPath))
			in, _ := os.Open(absBcPath)
			defer CheckDefer(func() error { return in.Close() })
			out, _ := os.Create(destFilePath)
			defer CheckDefer(func() error { return out.Close() })
			_, err := io.Copy(out, in)
			if err != nil {
				LogWarning("Copying bc to bitcode archive %v failed because %v\n", destFilePath, err)
			}
			err = out.Sync()
			if err != nil {
				LogWarning("Syncing bitcode archive %v failed because %v\n", destFilePath, err)
			}

		}
	}
}

func compileTimeLinkFiles(compilerExecName string, pr parserResult, objFiles []string) {
	var outputFile = pr.OutputFilename
	if outputFile == "" {
		outputFile = "a.out"
	}
	args := objFiles
	for _, larg := range pr.LinkArgs {
		args = append(args, larg)
	}
	args = append(args, "-o", outputFile)
	success, err := execCmd(compilerExecName, args, "")
	if !success {
		LogError("%v %v failed to link: %v.", compilerExecName, args, err)
	} else {
		LogInfo("LINKING: %v %v", compilerExecName, args)
	}
}

// Tries to build the specified source file to object
func buildObjectFile(compilerExecName string, pr parserResult, srcFile string, objFile string) {
	args := pr.CompileArgs[:]
	args = append(args, srcFile, "-c", "-o", objFile)
	success, err := execCmd(compilerExecName, args, "")
	if !success {
		LogError("Failed to build object file for %s because: %v\n", srcFile, err)
		//was LogFatal
		return
	}
}

// Tries to build the specified source file to bitcode
func buildBitcodeFile(compilerExecName string, pr parserResult, srcFile string, bcFile string) {
	args := pr.CompileArgs[:]
	args = append(args, "-emit-llvm", "-c", srcFile, "-o", bcFile)
	success, err := execCmd(compilerExecName, args, "")
	if !success {
		LogError("Failed to build bitcode file for %s because: %v\n", srcFile, err)
		//was LogFatal
		return
	}
}

// Tries to build object file
func execCompile(compilerExecName string, pr parserResult, wg *sync.WaitGroup, ok *bool) {
	defer (*wg).Done()
	//iam: strickly speaking we should do more work here depending on whether this is
	//     a compile only, a link only, or ...
	//     But for the now, we just remove forbidden arguments
	var success bool
	var err error
	if len(pr.ForbiddenFlags) > 0 {
		filteredArgs := pr.InputList[:0]
		for _, arg := range pr.InputList {
			found := false
			for _, bad := range pr.ForbiddenFlags {
				if bad == arg {
					found = true
					break
				}
			}
			if !found {
				filteredArgs = append(filteredArgs, arg)
			}
		}
		success, err = execCmd(compilerExecName, filteredArgs, "")
	} else {
		success, err = execCmd(compilerExecName, pr.InputList, "")
	}

	if !success {
		LogError("Failed to compile using given arguments:\n%v %v\nexit status: %v\n", compilerExecName, pr.InputList, err)
		*ok = false
	}
}

// GetCompilerExecName returns the full path of the executable
func GetCompilerExecName(compiler string) string {
	switch compiler {
	case "clang":
		if LLVMCCName != "" {
			return filepath.Join(LLVMToolChainBinDir, LLVMCCName)
		}
		return filepath.Join(LLVMToolChainBinDir, compiler)
	case "clang++":
		if LLVMCXXName != "" {
			return filepath.Join(LLVMToolChainBinDir, LLVMCXXName)
		}
		return filepath.Join(LLVMToolChainBinDir, compiler)
	default:
		LogError("The compiler %s is not supported by this tool.", compiler)
		// was LogFatal
		return ""
	}
}

//CheckDefer is used to check the return values of defers
func CheckDefer(f func() error) {
	if err := f(); err != nil {
		LogWarning("CheckDefer received error: %v\n", err)
	}
}
