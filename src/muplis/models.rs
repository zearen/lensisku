use super::dto::MuplisEntry;
use tokio_postgres::Row;

impl From<Row> for MuplisEntry {
    fn from(row: Row) -> Self {
        MuplisEntry {
            id: row.get("id"),
            lojban: row.get("lojban"),
            english: row.get("english"),
            rank: row.get("rank"),
        }
    }
}
