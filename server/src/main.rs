use std::{net::SocketAddr, path::PathBuf, time::Duration};

use anyhow::{Result, anyhow};
use serde::Deserialize;
use tracing::{error, info, warn};

use crate::{guestbook::Guestbook, router::build_router};

mod guestbook;
mod router;

#[derive(Debug, Deserialize)]
enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl LogLevel {
    fn from_str(s: impl AsRef<str>) -> Result<Self> {
        let s = s.as_ref();
        match s.to_lowercase().as_ref() {
            "trace" => Ok(Self::Trace),
            "debug" => Ok(Self::Debug),
            "info" => Ok(Self::Info),
            "warn" => Ok(Self::Warn),
            "error" => Ok(Self::Error),
            _ => Err(anyhow!("invalid log level '{}'", s)),
        }
    }

    fn to_tracing_level(&self) -> tracing::Level {
        match self {
            Self::Trace => tracing::Level::TRACE,
            Self::Debug => tracing::Level::DEBUG,
            Self::Info => tracing::Level::INFO,
            Self::Warn => tracing::Level::WARN,
            Self::Error => tracing::Level::ERROR,
        }
    }
}

async fn _main() -> Result<()> {
    let addr = std::env::var("NGILL_NET_GUESTBOOK_ADDR")?;
    let port = std::env::var("NGILL_NET_GUESTBOOK_PORT")?;
    let log_level: LogLevel = std::env::var("NGILL_NET_GUESTBOOK_LOG_LEVEL")
        .map(|s| LogLevel::from_str(&s).unwrap())
        .unwrap_or(LogLevel::Info);
    let store = PathBuf::from(std::env::var("NGILL_NET_GUESTBOOK_STORE")?);

    tracing_subscriber::fmt()
        .with_timer(tracing_subscriber::fmt::time::uptime())
        .with_max_level(log_level.to_tracing_level())
        .init();

    let sock = format!("{}:{}", addr, port);

    info!("socket: {}", sock);
    info!("store: {:?}", store);

    let gbh = Guestbook::for_store(store).await?;

    let app = build_router(gbh.clone());
    let listener = tokio::net::TcpListener::bind(sock).await?;

    let flush_gbh = gbh.clone();
    tokio::spawn(async move {
        loop {
            if let Err(e) = flush_gbh.flush().await {
                warn!("failed to flush: {e}");
            }

            // try and flush every minute
            tokio::time::sleep(Duration::from_mins(1)).await;
        }
    });

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;

    Err(anyhow!("guestbook server exited?"))
}

#[tokio::main]
async fn main() {
    if let Err(e) = _main().await {
        error!("fatal: {:#?}", e);
        std::process::exit(1);
    }
}
