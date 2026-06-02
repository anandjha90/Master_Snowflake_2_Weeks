-- Fails if any claim approved more than was claimed (data quality rule).
select claim_id, claim_amount, approved_amount
from {{ ref('fact_claims') }}
where approved_amount > claim_amount
