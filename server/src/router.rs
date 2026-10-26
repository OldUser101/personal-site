use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use tower_governor::{
    GovernorLayer,
    governor::{GovernorConfig, GovernorConfigBuilder},
};
use tracing::error;

use crate::guestbook::{Entry, GuestbookHandle};

#[derive(Debug, Clone)]
struct RouterState {
    gbh: GuestbookHandle,
}

struct GuestbookError(StatusCode, String);
type GuestbookResult<T> = Result<T, GuestbookError>;

impl IntoResponse for GuestbookError {
    fn into_response(self) -> axum::response::Response {
        error!("request error: {}: {}", self.0, self.1);
        (self.0, self.1).into_response()
    }
}

async fn get_entries(State(state): State<RouterState>) -> GuestbookResult<Json<Vec<Entry>>> {
    Ok(Json(state.gbh.get_entries().await))
}

async fn add_entry(
    State(state): State<RouterState>,
    Json(payload): Json<Entry>,
) -> GuestbookResult<()> {
    state
        .gbh
        .put_entry(payload)
        .await
        .map_err(|e| GuestbookError(StatusCode::BAD_REQUEST, e.to_string()))
}

pub fn build_router(gbh: GuestbookHandle) -> Router {
    let get_conf = GovernorConfig::default();
    let post_conf = GovernorConfigBuilder::default()
        .per_second(30)
        .burst_size(1)
        .finish()
        .unwrap();

    Router::new()
        .route(
            "/entries",
            get(get_entries).route_layer(GovernorLayer::new(get_conf)),
        )
        .route(
            "/entries",
            post(add_entry).route_layer(GovernorLayer::new(post_conf)),
        )
        .with_state(RouterState { gbh })
}
