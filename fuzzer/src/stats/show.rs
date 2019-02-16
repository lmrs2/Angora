use super::ChartStats;
use crate::{branches::GlobalBranches, depot::Depot};
use angora_common::defs;
use std::{
    fs,
    path::{PathBuf},
    io::Write,
    sync::{Arc, RwLock},
};


pub fn init_stats(
    stats: &Arc<RwLock<ChartStats>>,
    path: PathBuf,
) -> fs::File {
    let mut log_file = match fs::File::create(path) {
        Ok(a) => a,
        Err(e) => {
            error!("FATAL: Could not create log file: {:?}", e);
            panic!();
        }
    };

    let s = stats.read().expect("Could not read from stats.");

    writeln!(log_file, "{}", s.mini_header())
            .expect("Could not write minilog.");

    log_file
}

pub fn show_stats(
    log_f: &mut fs::File,
    depot: &Arc<Depot>,
    gb: &Arc<GlobalBranches>,
    stats: &Arc<RwLock<ChartStats>>,
    show_ui: bool,
) {
    stats
        .write()
        .expect("Could not write stats.")
        .sync_from_global(depot, gb);

    let dir = depot
        .dirs
        .inputs_dir
        .parent()
        .expect("Could not get parent directory.");
    let mut log_s = fs::File::create(dir.join(defs::CHART_STAT_FILE))
        .expect("Could not create chart stat file.");
    {
        let s = stats.read().expect("Could not read from stats.");
        if show_ui {
            println!("{}", *s);
        }
        
        writeln!(log_f, "{}", s.mini_log()).expect("Could not write minilog.");
        write!(
            log_s,
            "{}",
            serde_json::to_string(&*s).expect("Could not serialize!")
        )
        .expect("Unable to write!");
    }
}
