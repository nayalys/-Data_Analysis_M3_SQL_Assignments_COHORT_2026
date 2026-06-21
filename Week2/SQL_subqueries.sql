USE coffeeshop_db;

-- =========================================================
-- SUBQUERIES & NESTED LOGIC PRACTICE
-- =========================================================

-- Q1) Scalar subquery (AVG benchmark):
--     List products priced above the overall average product price.
--     Return product_id, name, price.

select product_id, name, price
from products
where price > (select AVG(price) from products);

-- Q2) Scalar subquery (MAX within category):
--     Find the most expensive product(s) in the 'Beans' category.
--     (Return all ties if more than one product shares the max price.)
--     Return product_id, name, price.

select product_id,name, price 
from products
where price= ( select MAX(price) 
               from products 
               join categories on categories.category_id= products.category_id 
			   where categories.name = 'beans');

-- Q3) List subquery (IN with nested lookup):
--     List customers who have purchased at least one product in the 'Merch' category.
--     Return customer_id, first_name, last_name.
--     Hint: Use a subquery to find the category_id for 'Merch', then a subquery to find product_ids.
-- customers,orders, order_items, categories, products

select customers.customer_id, customers.first_name, customers.last_name
from customers
join orders on customers.customer_id= orders.customer_id 
join order_items on order_items.order_id = orders.order_id
where (order_items.quantity>=1) and 
      (order_items. product_id in (select products.product_id 
								   from products
								   join order_items on products.product_id = order_items.product_id
								   join categories on products.category_id = categories.category_id
								   where categories.name = 'Merch') 
	   )
;

-- Q4) List subquery (NOT IN / anti-join logic):
--     List products that have never been ordered (their product_id never appears in order_items).
--     Return product_id, name, price.

select product_id, name , price
from products
where product_id not in (select product_id from order_items);

-- Q5) Table subquery (derived table + compare to overall average):
--     Build a derived table that computes total_units_sold per product 
--     (SUM(order_items.quantity) grouped by product_id).
--     Then return only products whose total_units_sold is greater than the
--     average total_units_sold across all products.
--     Return product_id, product_name, total_units_sold.

SELECT 
    product_id,
    product_name,
    total_units_sold
FROM (
    -- Derived table: total units sold per product (0 if never ordered)
    SELECT 
        p.product_id,
        p.name AS product_name,
        COALESCE(SUM(oi.quantity), 0) AS total_units_sold
    FROM products p
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY p.product_id, p.name
) AS product_totals
WHERE total_units_sold > (
    -- Scalar subquery: average total_units_sold across all products
    SELECT AVG(total_units_sold)
    FROM (
        SELECT COALESCE(SUM(oi.quantity), 0) AS total_units_sold
        FROM products p
        LEFT JOIN order_items oi ON p.product_id = oi.product_id
        GROUP BY p.product_id
    ) AS avg_base
);

