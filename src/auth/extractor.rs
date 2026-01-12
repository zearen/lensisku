use crate::auth::{models::Claims, permissions::PermissionCache};
use actix_web::{dev::ServiceRequest, web, Error, HttpMessage};
use log::debug;
use std::collections::HashSet;

pub async fn extract_authorities(req: &ServiceRequest) -> Result<HashSet<String>, Error> {
    let mut authorities = HashSet::new();

    // Get claims from request extensions
    // Extract claims data before await
    let role = if let Some(claims) = req.extensions().get::<Claims>() {
        debug!("Processing claims for user: {}", claims.username);

        // Add email confirmation status
        if !claims.email_confirmed {
            authorities.insert("UNCONFIRMED".to_string());
        }

        Some(claims.role.clone())
    } else {
        debug!("No claims found in request");
        None
    };

    // Add permissions based on role if we have one
    if let Some(role) = role {
        if let Some(perm_cache) = req.app_data::<web::Data<PermissionCache>>() {
            let permissions = perm_cache.get_permissions_for_role(role).await;
            for permission in permissions {
                authorities.insert(permission.name);
            }
        } else {
            debug!("Permission cache not found in app data");
        }
    }

    debug!("Granted authorities: {:?}", authorities);

    Ok(authorities)
}
