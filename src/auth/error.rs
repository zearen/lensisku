#[derive(Debug)]
pub(crate) enum EmailError {
    SendError(String),
    ConfigError(String),
}

impl std::fmt::Display for EmailError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EmailError::SendError(msg) => write!(f, "Send error: {}", msg),
            EmailError::ConfigError(msg) => write!(f, "Configuration error: {}", msg),
        }
    }
}

impl From<EmailError> for SignupError {
    fn from(error: EmailError) -> Self {
        SignupError::EmailError(error)
    }
}

#[derive(Debug)]
pub enum PasswordHashError {
    BcryptError(bcrypt::BcryptError),
    InvalidHashFormat,
}

impl std::fmt::Display for PasswordHashError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PasswordHashError::BcryptError(e) => write!(f, "Bcrypt error: {}", e),
            PasswordHashError::InvalidHashFormat => write!(f, "Invalid hash format"),
        }
    }
}

impl std::error::Error for PasswordHashError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            PasswordHashError::BcryptError(e) => Some(e),
            PasswordHashError::InvalidHashFormat => None,
        }
    }
}

impl From<bcrypt::BcryptError> for PasswordHashError {
    fn from(error: bcrypt::BcryptError) -> Self {
        PasswordHashError::BcryptError(error)
    }
}

#[derive(Debug)]
pub enum SignupError {
    DatabaseError(tokio_postgres::Error),
    PoolError(deadpool::managed::PoolError<tokio_postgres::Error>),
    HashError(PasswordHashError),
    TokenError(jsonwebtoken::errors::Error),
    EmailError(EmailError),
}

impl std::fmt::Display for SignupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SignupError::DatabaseError(e) => write!(f, "Database error: {}", e),
            SignupError::PoolError(e) => write!(f, "Connection pool error: {}", e),
            SignupError::HashError(e) => write!(f, "Password hashing error: {:?}", e),
            SignupError::TokenError(e) => write!(f, "Token generation error: {}", e),
            SignupError::EmailError(e) => write!(f, "Email error: {}", e),
        }
    }
}

impl std::error::Error for SignupError {}

impl From<tokio_postgres::Error> for SignupError {
    fn from(error: tokio_postgres::Error) -> Self {
        SignupError::DatabaseError(error)
    }
}

impl From<deadpool::managed::PoolError<tokio_postgres::Error>> for SignupError {
    fn from(error: deadpool::managed::PoolError<tokio_postgres::Error>) -> Self {
        SignupError::PoolError(error)
    }
}

impl From<PasswordHashError> for SignupError {
    fn from(error: PasswordHashError) -> Self {
        SignupError::HashError(error)
    }
}

impl From<jsonwebtoken::errors::Error> for SignupError {
    fn from(error: jsonwebtoken::errors::Error) -> Self {
        SignupError::TokenError(error)
    }
}
