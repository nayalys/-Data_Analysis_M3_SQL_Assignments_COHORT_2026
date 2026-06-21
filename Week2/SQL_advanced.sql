USE coffeeshop_db;

-- =========================================================
-- ADVANCED SQL ASSIGNMENT
-- Subqueries, CTEs, Window Functions, Views
-- =========================================================
-- Notes:
-- - Unless a question says otherwise, use orders with status = 'paid'.
-- - Write ONE query per prompt.
-- - Keep results readable (use clear aliases, ORDER BY where it helps).

-- =========================================================
-- Q1) Correlated subquery: Above-average order totals (PAID only)
-- =========================================================
-- For each PAID order, compute order_total (= SUM(quantity * products.price)).
-- Return: order_id, customer_name, store_name, order_datetime, order_total.
-- Filter to orders where order_total is greater than the average PAID order_total
-- for THAT SAME store (correlated subquery).
-- Sort by store_name, then order_total DESC.

-- Tables to work:
-- Orders: status ='paid', Order_Items, Customers,Products

with paid_order_totals AS (
SELECT o.order_id, o.store_id, o.customer_id, o.order_datetime,
SUM(oi.quantity * p.price) AS order_total
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.status = 'PAID'
GROUP BY o.order_id, o.store_id, o.customer_id, o.order_datetime
)
SELECT pot.order_id, cu.first_name customer_name, st.name store_name,pot.order_datetime, pot.order_total
FROM paid_order_totals pot
JOIN customers cu ON pot.customer_id = cu.customer_id
JOIN stores st ON pot.store_id = st.store_id
WHERE pot.order_total > (
SELECT AVG(pot2.order_total)
FROM paid_order_totals pot2
WHERE pot2.store_id = pot.store_id
)
ORDER BY st.name, pot.order_total DESC
;
-- =========================================================
-- Q2) CTE: Daily revenue and 3-day rolling average (PAID only)
-- =========================================================
-- Using a CTE, compute daily revenue per store:
--   revenue_day = SUM(quantity * products.price) grouped by store_id and DATE(order_datetime).
-- Then, for each store and date, return:
--   store_name, order_date, revenue_day,
--   rolling_3day_avg = average of revenue_day over the current day and the prior 2 days.
-- Use a window function for the rolling average.
-- Sort by store_name, order_date.

with daily_revenue_per_store as(
select 
        o.store_id,
        DATE(o.order_datetime) AS order_date, 
        SUM(oi.quantity * p.price) as revenue_day
from orders o
join order_items oi on oi.order_id = o.order_id
join products p on oi.product_id = p.product_id
GROUP BY o.store_id, DATE(o.order_datetime)
), 
daily_with_rolling AS (
    SELECT
        store_id,
        order_date,
        revenue_day,
        AVG(revenue_day) OVER (
            PARTITION BY store_id 
            ORDER BY order_date 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS rolling_3day_avg
    FROM daily_revenue_per_store
)
SELECT
      st.name store_name, dr.order_date, dr.revenue_day, dr.rolling_3day_avg
FROM daily_with_rolling dr
JOIN stores st on st.store_id= dr.store_id
ORDER BY store_name, dr.order_date
;
-- =========================================================
-- Q3) Window function: Rank customers by lifetime spend (PAID only)
-- =========================================================
-- Compute each customer's total spend across ALL stores (PAID only).
-- Return: customer_id, customer_name, total_spend,
--         spend_rank (DENSE_RANK by total_spend DESC).
-- Also include percent_of_total = customer's total_spend / total spend of all customers.
-- Sort by total_spend DESC.

with customer_spend as (
select 
	  cu.customer_id, 
      concat (cu.first_name,' ',cu.last_name) customer_name,
      SUM(oi.quantity * p.price) total_spend      
from customers cu
left join orders o on o.customer_id= cu.customer_id  
join order_items oi on oi.order_id = o.order_id
join products p on p.product_id = oi.product_id
WHERE o.status = 'PAID'
GROUP BY cu.customer_id, cu.first_name, cu.last_name
)
select 
       customer_id, customer_name, total_spend,
       dense_rank() over (order by total_spend desc) as spend_rank,
	   ROUND( 100.0 * total_spend / NULLIF(SUM(total_spend) OVER (), 0), 2) AS percent_of_total
from customer_spend
order by total_spend desc
;

-- =========================================================
-- Q4) CTE + window: Top product per store by revenue (PAID only)
-- =========================================================
-- For each store, find the top-selling product by REVENUE (not units).
-- Revenue per product per store = SUM(quantity * products.price).
-- Return: store_name, product_name, category_name, product_revenue.
-- Use a CTE to compute product_revenue, then a window function (ROW_NUMBER)
-- partitioned by store to select the top 1.
-- Sort by store_name. 
 WITH store_product_revenue AS (
 select 
        st.store_id,st.name store_name, p.product_id, p.name product_name, ca.name category_name, 
        SUM(oi.quantity * p.price) as product_revenue
  from  orders o
  join order_items oi on oi.order_id = o.order_id
  join products p on oi.product_id = p.product_id
  join stores st on st.store_id = o.store_id
  join categories ca on ca.category_id = p.category_id
  where o.status='paid'
  group by  st.store_id, store_name, p.product_id, product_name, category_name
  ),
  ranked_products as (
  select 
        store_name, 
        product_name, 
        category_name,
        product_revenue,
        row_number() over (partition by store_id order by product_revenue desc, product_name) as rn
  from store_product_revenue
  )
  select 
		store_name,
        product_name,
        category_name,
        product_revenue
  from ranked_products
  where rn =1
  order by store_name
  ;
-- =========================================================
-- Q5) Subquery: Customers who have ordered from ALL stores (PAID only)
-- =========================================================
-- Return customers who have at least one PAID order in every store in the stores table.
-- Return: customer_id, customer_name.
-- Hint: Compare count(distinct store_id) per customer to (select count(*) from stores).

SELECT cu.customer_id, CONCAT(cu.first_name, ' ', cu.last_name) AS customer_name
FROM customers cu
JOIN orders o ON cu.customer_id = o.customer_id AND o.status = 'PAID'
GROUP BY cu.customer_id, cu.first_name, cu.last_name
HAVING COUNT(DISTINCT o.store_id) = (SELECT COUNT(*) FROM stores);

-- =========================================================
-- Q6) Window function: Time between orders per customer (PAID only)
-- =========================================================
-- For each customer, list their PAID orders in chronological order and compute:
--   prev_order_datetime (LAG),
--   minutes_since_prev (difference in minutes between current and previous order).
-- Return: customer_name, order_id, order_datetime, prev_order_datetime, minutes_since_prev.
-- Only show rows where prev_order_datetime is NOT NULL.
-- Sort by customer_name, order_datetime.

with timediff_customer_orders  as (
select 
       o.customer_id,
       o.order_id order_id,
       concat( cu.first_name,' ',cu.last_name) customer_name,
       o.order_datetime order_datetime, 
       LAG(o.order_datetime) OVER (PARTITION BY o.customer_id ORDER BY o.order_datetime) as prev_order_datetime,
       TIMESTAMPDIFF(MINUTE, 
                  LAG(o.order_datetime) OVER (PARTITION BY o.customer_id ORDER BY o.order_datetime), 
                  o.order_datetime) AS minutes_since_prev
from orders o 
join customers cu on cu.customer_id=o.customer_id
where o.status ='paid' 
order by customer_name, order_datetime
)
select 
       customer_name,
       order_id,
       order_datetime,
       prev_order_datetime,
       minutes_since_prev
	from timediff_customer_orders
    where prev_order_datetime is not null
    order by customer_name, order_datetime
    ;
    
-- =========================================================
-- Q7) View: Create a reusable order line view for PAID orders
-- =========================================================
-- Create a view named v_paid_order_lines that returns one row per PAID order item:
--   order_id, order_datetime, store_id, store_name,
--   customer_id, customer_name,
--   product_id, product_name, category_name,
--   quantity, unit_price (= products.price),
--   line_total (= quantity * products.price)
--
-- After creating the view, write a SELECT that uses the view to return:
--   store_name, category_name, revenue
-- where revenue is SUM(line_total),
-- sorted by revenue DESC.

create view v_paid_order_lines as
select  
        o.order_id, o.order_datetime, 
        st.store_id, st.name store_name,
        cu.customer_id, concat(cu.first_name, ' ',cu.last_name) customer_name,
        p.product_id, p.name product_name, ca.name category_name,
		oi.quantity, p.price as unit_price,
        oi.quantity * p.price as line_total
from orders o
join stores st on st.store_id = o.store_id
join customers cu on cu.customer_id= o.customer_id
join order_items oi on oi.order_id= o.order_id
join products p on p.product_id= oi.product_id
join categories ca on  ca.category_id = p.category_id
where o.status = 'paid';
select
	  store_name,
      category_name, 
      SUM(line_total) as revenue
from v_paid_order_lines
group by store_name, category_name   
order by revenue desc;

-- ========================================================
-- Q8) View + window: Store revenue share by payment method (PAID only)
-- =========================================================
-- Create a view named v_paid_store_payments with:
--   store_id, store_name, payment_method, revenue
-- where revenue is total PAID revenue for that store/payment_method.
--
-- Then query the view to return:
--   store_name, payment_method, revenue,
--   store_total_revenue (window SUM over store),
--   pct_of_store_revenue (= revenue / store_total_revenue)
-- Sort by store_name, revenue DESC.

create view v_paid_store_payments as
select 
       st.store_id, st.name store_name, 
       o.payment_method, 
       SUM(oi.quantity * p.price) as revenue
from orders o
join stores st on st.store_id = o.store_id
join order_items oi on oi.order_id=o.order_id
join products p on oi.product_id = p.product_id
where o.status ='paid'
group by st.store_id, store_name, payment_method;

select 
	 store_name, payment_method, revenue,
     SUM(revenue) OVER (PARTITION BY store_name) as store_total_revenue,
     round (revenue * 100.0 / NULLIF(SUM(revenue) OVER (PARTITION BY store_name), 0),2) as pct_of_store_revenue
from v_paid_store_payments
order by store_name, revenue DESC;

-- =========================================================
-- Q9) CTE: Inventory risk report (low stock relative to sales)
-- =========================================================
-- Identify items where on_hand is low compared to recent demand:
-- Using a CTE, compute total_units_sold per store/product for PAID orders.
-- Then join inventory to that result and return rows where:
--   on_hand < total_units_sold
-- Return: store_name, product_name, on_hand, total_units_sold, units_gap (= total_units_sold - on_hand)
-- Sort by units_gap DESC.

with total_units_sold as (  
select 
      o.store_id store_id, 
      oi.product_id product_id, 
	  SUM(oi.quantity) total_units_sold
from orders o
join order_items oi on oi.order_id = o.order_id
join products p on p.product_id = oi.product_id
where o.status='paid'
group by o.store_id, oi.product_id
)
select 
       st.name store_name, 
       p.name product_name, 
       inv.on_hand, 
       tus.total_units_sold, 
	   (tus.total_units_sold - inv.on_hand) as units_gap
	from total_units_sold tus
    join inventory inv on tus.store_id = inv.store_id and tus.product_id = inv.product_id 
    join stores st on tus.store_id = st.store_id
    join products p on tus.product_id = p.product_id
    where inv.on_hand < tus.total_units_sold
    order by units_gap desc;
    
-- The results of this query: 0 rows returned, it means any product is low in the stock.

    
    
