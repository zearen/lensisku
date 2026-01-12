use redis::{AsyncCommands, Client};
use std::time::Duration;

pub struct RateLimiter {
    client: Client,
    window: Duration,
    max_requests: u32,
}

impl RateLimiter {
    pub fn new(
        redis_url: &str,
        window: Duration,
        max_requests: u32,
    ) -> Result<Self, redis::RedisError> {
        Ok(Self {
            client: Client::open(redis_url)?,
            window,
            max_requests,
        })
    }

    pub async fn check_rate_limit(&self, email: &str) -> Result<bool, redis::RedisError> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        let key = format!("password_reset:{}", email);

        let count: Option<u32> = conn.get(&key).await?;
        match count {
            Some(count) if count >= self.max_requests => Ok(false),
            Some(_) => {
                let _: () = conn.incr(&key, 1).await?;
                Ok(true)
            }
            None => {
                let _: () = conn.set_ex(&key, 1, self.window.as_secs()).await?;
                Ok(true)
            }
        }
    }
}

pub struct PasswordResetLimiter {
    limiter: RateLimiter,
}

impl PasswordResetLimiter {
    pub fn new(redis_url: &str) -> Result<Self, redis::RedisError> {
        Ok(Self {
            limiter: RateLimiter::new(redis_url, std::time::Duration::from_secs(4 * 60 * 60), 1)?,
        })
    }

    pub async fn check_rate_limit(&self, email: &str) -> Result<bool, redis::RedisError> {
        self.limiter.check_rate_limit(email).await
    }
}

pub struct EmailConfirmationLimiter {
    client: Client,
    base_window: Duration,
    max_attempts: u32,
}

impl EmailConfirmationLimiter {
    pub fn new(redis_url: &str) -> Result<Self, redis::RedisError> {
        Ok(Self {
            client: Client::open(redis_url)?,
            base_window: Duration::from_secs(30 * 60), // 30 minutes base window
            max_attempts: 5,                           // Maximum 5 attempts
        })
    }

    pub async fn check_rate_limit(&self, email: &str) -> Result<bool, redis::RedisError> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        let key = format!("email_confirmation_resend:{}", email);

        let attempts: Option<u32> = conn.get(&key).await?;
        match attempts {
            Some(count) => {
                if count >= self.max_attempts {
                    return Ok(false);
                }

                // Calculate exponential backoff window
                let window = self.base_window.as_secs() * 2u64.pow(count);
                let _: () = conn.set_ex(&key, count + 1, window).await?;
                Ok(true)
            }
            None => {
                let _: () = conn.set_ex(&key, 1, self.base_window.as_secs()).await?;
                Ok(true)
            }
        }
    }
}
