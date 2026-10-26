use std::{
    collections::VecDeque,
    path::PathBuf,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use tokio::{
    fs::File,
    io::{AsyncReadExt, AsyncWriteExt},
    sync::Mutex,
};
use tracing::{debug, info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entry {
    pub name: String,
    pub message: String,
    #[serde(default = "default_entry_ts")]
    pub ts: u64,
}

fn default_entry_ts() -> u64 {
    0u64
}

#[derive(Debug)]
pub struct Guestbook {
    file: tokio::fs::File,
    entries: Vec<Entry>,
    entry_queue: VecDeque<Entry>,
}

#[derive(Debug, Clone)]
pub struct GuestbookHandle(Arc<Mutex<Guestbook>>);

impl GuestbookHandle {
    pub async fn flush(&self) -> Result<()> {
        let mut gb = self.0.lock().await;
        gb.flush().await
    }

    pub async fn get_entries(&self) -> Vec<Entry> {
        let gb = self.0.lock().await;
        gb.get_entries()
    }

    pub async fn put_entry(&self, entry: Entry) -> Result<()> {
        let mut gb = self.0.lock().await;
        gb.put_entry(entry).await
    }
}

impl Guestbook {
    pub async fn for_store(mut store: PathBuf) -> Result<GuestbookHandle> {
        store.push("guestbook.jsonl");

        let mut file = File::options()
            .create(true)
            .append(true)
            .read(true)
            .open(&store)
            .await?;

        debug!("opened guestbook: {:?}", store);

        let mut content = String::new();
        file.read_to_string(&mut content).await?;

        let mut entries: Vec<Entry> = Vec::new();
        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }

            entries.push(serde_json::from_str(line)?);
        }

        let gb = Self {
            file,
            entries,
            entry_queue: VecDeque::new(),
        };

        Ok(GuestbookHandle(Arc::new(Mutex::new(gb))))
    }

    async fn flush(&mut self) -> Result<()> {
        let mut flushed = 0;

        while !self.entry_queue.is_empty() {
            let mut bytes = serde_json::to_vec(&self.entry_queue[0])?;
            bytes.push(b'\n');

            self.file.write_all(&bytes).await?;
            self.entry_queue.pop_front();

            flushed += 1;
        }

        if flushed > 0 {
            info!("flushed {} entries", flushed);
        }

        Ok(())
    }

    fn get_entries(&self) -> Vec<Entry> {
        // i know
        self.entries.clone()
    }

    async fn put_entry(&mut self, mut entry: Entry) -> Result<()> {
        entry.name = entry.name.trim().to_string();
        entry.message = entry.message.trim().to_string();

        if entry.name.is_empty() {
            return Err(anyhow!("entry name cannot be empty"));
        }
        if entry.message.is_empty() {
            return Err(anyhow!("entry message cannot be empty"));
        }
        if entry.name.len() > 100 {
            return Err(anyhow!("entry name cannot exceed 100 characters"));
        }
        if entry.message.len() > 1000 {
            return Err(anyhow!("entry message cannot exceed 1000 characters"));
        }

        let now = SystemTime::now();
        let ts = now.duration_since(UNIX_EPOCH)?.as_secs();
        entry.ts = ts;

        self.entries.push(entry.clone());
        self.entry_queue.push_back(entry.clone());

        info!(
            "push entry: name={}, message={}, ts={}",
            entry.name, entry.message, entry.ts
        );

        if let Err(e) = self.flush().await {
            warn!("failed to flush entries: {:#?}", e);
        }

        Ok(())
    }
}
