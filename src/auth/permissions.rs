use crate::auth::Claims;
use actix_web::{dev::ServiceRequest, web, Error, HttpMessage};
use deadpool_postgres::Pool;
use futures::future::{self, Future, Ready};
use std::collections::HashMap;
use std::pin::Pin;
use std::sync::Arc;
use tokio::sync::RwLock;

use super::models::{Permission, UserRole};

pub struct PermissionCache {
    pool: Pool,
    cache: RwLock<HashMap<String, Vec<Permission>>>,
}

impl PermissionCache {
    // ELI5: We're making a special box (Arc) to hold our permission rules that can be safely shared
    // across different parts of our web server. Like a rulebook that many teachers can look at
    // at the same time to check if students are allowed to do something.
    pub fn new(pool: Pool) -> Arc<Self> {
        Arc::new(Self {
            pool,
            cache: RwLock::new(HashMap::new()),
        })
    }

    pub async fn load_permissions(&self) -> Result<(), Box<dyn std::error::Error>> {
        let client = self.pool.get().await?;
        let rows = client
            .query(
                "SELECT r.role::text as role, p.name, p.description
                 FROM role_permissions r 
                 JOIN permissions p ON r.permission_id = p.id",
                &[],
            )
            .await?;

        let mut cache = HashMap::new();
        for row in rows {
            let role: String = row.get("role");
            let permission = Permission {
                name: row.get("name"),
                description: row.get("description"),
            };
            cache.entry(role).or_insert_with(Vec::new).push(permission);
        }

        let mut write_cache = self.cache.write().await;
        *write_cache = cache;

        Ok(())
    }

    pub async fn has_permission(&self, role: String, permission_name: &str) -> bool {
        let cache = self.cache.read().await;
        cache
            .get(&role)
            .map(|perms| perms.iter().any(|p| p.name == permission_name))
            .unwrap_or(false)
    }

    pub async fn get_permissions_for_role(&self, role: String) -> Vec<Permission> {
        let cache = self.cache.read().await;
        cache.get(&role).map(|v| v.to_vec()).unwrap_or_default()
    }
}

type CheckPermissionFuture = Pin<Box<dyn Future<Output = Result<ServiceRequest, Error>>>>;

pub fn check_permission(
    permission: &'static str,
) -> impl Fn(ServiceRequest) -> CheckPermissionFuture {
    move |req: ServiceRequest| {
        let fut = async move {
            // Extract claims first
            let claims = {
                let extensions = req.extensions();
                match extensions.get::<Claims>() {
                    Some(claims) => {
                        // Always deny unconfirmed users except for confirming their email
                        if claims.role == UserRole::Unconfirmed.to_string() {
                            return Err(actix_web::error::ErrorForbidden("Email not confirmed"));
                        }
                        claims.clone()
                    }
                    None => {
                        return Err(actix_web::error::ErrorUnauthorized("No valid auth token"));
                    }
                }
            };

            // Check if user is disabled
            if let Some(pool) = req.app_data::<web::Data<Pool>>() {
                let client = pool.get().await.map_err(|e| {
                    actix_web::error::ErrorInternalServerError(format!("Database error: {}", e))
                })?;

                let is_disabled: bool = client
                    .query_one(
                        "SELECT disabled FROM users WHERE userid = $1",
                        &[&claims.sub],
                    )
                    .await
                    .map_err(|e| {
                        actix_web::error::ErrorInternalServerError(format!("Database error: {}", e))
                    })?
                    .get("disabled");

                if is_disabled {
                    return Err(actix_web::error::ErrorForbidden("Account is disabled"));
                }
            }

            if let Some(perm_cache) = req.app_data::<Arc<PermissionCache>>() {
                let has_permission = perm_cache
                    .has_permission(claims.role.to_string(), permission)
                    .await;
                if has_permission {
                    Ok(req)
                } else {
                    Err(actix_web::error::ErrorForbidden("Insufficient permissions"))
                }
            } else {
                Err(actix_web::error::ErrorInternalServerError(
                    "Permission cache not found",
                ))
            }
        };

        Box::pin(fut)
    }
}

pub struct CheckPermission(pub &'static str);

impl<S> actix_web::dev::Transform<S, ServiceRequest> for CheckPermission
where
    S: actix_web::dev::Service<
            ServiceRequest,
            Response = actix_web::dev::ServiceResponse,
            Error = actix_web::Error,
        > + 'static,
{
    type Response = actix_web::dev::ServiceResponse;
    type Error = actix_web::Error;
    type Transform = CheckPermissionMiddleware<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        // ELI5: We're wrapping our web service in a special protective box (Arc) so many different
        // web requests can safely use it at the same time, like having multiple copies of the same
        // security guard checking people's tickets at different doors.
        future::ok(CheckPermissionMiddleware {
            service: Arc::new(service),
            permission: self.0,
        })
    }
}

pub struct CheckPermissionMiddleware<S> {
    service: Arc<S>,
    permission: &'static str,
}

impl<S> actix_web::dev::Service<ServiceRequest> for CheckPermissionMiddleware<S>
where
    S: actix_web::dev::Service<
            ServiceRequest,
            Response = actix_web::dev::ServiceResponse,
            Error = actix_web::Error,
        > + 'static,
{
    type Response = actix_web::dev::ServiceResponse;
    type Error = actix_web::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>>>>;

    actix_web::dev::forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let fut = check_permission(self.permission)(req);
        // ELI5: We're making a new copy of our service's protective box (Arc clone) so this specific
        // web request can safely use it without interfering with other requests, like making a copy
        // of a key that many people can use at the same time.
        let service = Arc::clone(&self.service);

        Box::pin(async move {
            match fut.await {
                Ok(req) => service.call(req).await,
                Err(e) => Err(e),
            }
        })
    }
}
