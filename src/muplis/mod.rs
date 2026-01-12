pub mod controller;
pub mod dto;
mod models;
mod service;

use actix_web::web;
pub use service::*;

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(web::scope("muplis").service(controller::search_muplis));
}
