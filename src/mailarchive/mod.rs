pub mod controller;
pub mod dto;
pub mod models;
mod service;

use actix_web::web;
pub use dto::*;
pub use models::Message;
pub use service::{check_for_new_emails, import_maildir};

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("mail")
            .service(controller::search_messages)
            .service(controller::get_message)
            .service(controller::show_thread)
            .service(controller::vote_spam_message),
    );
}
