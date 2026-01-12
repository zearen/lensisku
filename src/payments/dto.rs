use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use validator::Validate;

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreatePaymentRequest {
    #[validate(range(min = 50))] // Minimum 50 cents
    pub amount_cents: u64,
    #[validate(length(min = 3, max = 3))]
    pub currency: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CreatePaymentResponse {
    pub payment_id: String,
    pub redirect_url: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BalanceResponse {
    pub balance_cents: u64,
    pub premium_expires_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct WebhookResponse {
    pub success: bool,
    pub message: String,
}

// Added based on task requirements:

#[derive(Debug, Serialize, Deserialize, ToSchema, Validate)]
pub struct CreateSubscriptionRequest {
    pub plan_id: String,
    pub custom_id: Option<String>,
    pub start_time: Option<String>, // ISO 8601 format, e.g., "2024-12-01T00:00:00Z"
                                    // Consider adding application_context if needed
                                    // pub application_context: Option<PayPalApplicationContextDto>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalSubscriberNameDto {
    pub given_name: Option<String>,
    pub surname: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalShippingAddressDto {
    pub address_line_1: Option<String>,
    pub admin_area_2: Option<String>, // City
    pub postal_code: Option<String>,
    pub country_code: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalSubscriberDto {
    pub email_address: Option<String>,
    pub payer_id: Option<String>,
    pub name: Option<PayPalSubscriberNameDto>,
    pub shipping_address: Option<PayPalShippingAddressDto>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalMoneyDto {
    pub currency_code: String,
    pub value: String,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalCycleExecutionDto {
    pub tenure_type: String, // e.g., "REGULAR", "TRIAL"
    pub sequence: i32,
    pub cycles_completed: i32,
    pub cycles_remaining: Option<i32>,
    pub total_cycles: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalLastPaymentDetailsDto {
    pub amount: Option<PayPalMoneyDto>,
    pub time: Option<String>, // ISO 8601 format
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalSubscriptionBillingInfoDto {
    pub outstanding_balance: Option<PayPalMoneyDto>,
    pub cycle_executions: Option<Vec<PayPalCycleExecutionDto>>,
    pub last_payment: Option<PayPalLastPaymentDetailsDto>,
    pub next_billing_time: Option<String>, // ISO 8601 format
    pub failed_payments_count: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalLink {
    pub href: String,
    pub rel: String,
    #[serde(rename = "method", skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PayPalSubscriptionDto {
    pub id: String, // PayPal's subscription ID
    pub plan_id: String,
    pub status: String, // e.g., "APPROVAL_PENDING", "ACTIVE", "CANCELLED"
    pub status_update_time: Option<String>, // ISO 8601 format
    pub start_time: String, // ISO 8601 format
    pub quantity: Option<String>,
    pub shipping_amount: Option<PayPalMoneyDto>,
    pub subscriber: Option<PayPalSubscriberDto>,
    pub billing_info: Option<PayPalSubscriptionBillingInfoDto>,
    pub create_time: Option<String>, // ISO 8601 format
    pub update_time: Option<String>, // ISO 8601 format
    pub custom_id: Option<String>,
    pub plan_overridden: Option<bool>,
    pub links: Vec<PayPalLink>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct CancelSubscriptionRequestDto {
    pub reason: String,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct SubscriptionWebhookEventResource {
    pub id: String, // Subscription ID
    pub create_time: Option<String>,
    pub resource_type: String, // e.g., "subscription"
    pub event_type: String,    // e.g., "BILLING.SUBSCRIPTION.ACTIVATED"
    pub summary: String,
    pub resource: PayPalSubscriptionDto, // The actual subscription object
    pub links: Option<Vec<PayPalLink>>,
}
