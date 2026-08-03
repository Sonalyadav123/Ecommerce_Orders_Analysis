CREATE TABLE staging_orders (
    order_id TEXT,
    customer_name TEXT,
    customer_email TEXT,
    customer_phone TEXT,
    customer_city TEXT,
    product_name TEXT,
    category TEXT,
    seller_name TEXT,
    seller_city TEXT,
    unit_price TEXT,
    quantity TEXT,
    discount_pct TEXT,
    total_amount TEXT,
    order_date TEXT,
    payment_method TEXT,
    delivery_status TEXT,
    rating TEXT,
    review_comment TEXT
);

TRUNCATE TABLE staging_orders;

SELECT * FROM staging_orders;

-- 1. Extra spaces

UPDATE staging_orders
SET customer_name = TRIM(customer_name),
    customer_city = TRIM(customer_city),
	product_name = TRIM(product_name);

-- 2. Text Standardization

UPDATE staging_orders
SET customer_city = INITCAP(customer_city),
    seller_city = INITCAP(seller_city),
	payment_method = UPPER(payment_method),
	delivery_status = INITCAP(delivery_status);
	
-- 3. Spelling Fix

UPDATE staging_orders
SET customer_city = CASE
    WHEN customer_city IN('banglore','bangalore','bengaluru') THEN 'Bangalore'
    WHEN customer_city IN ('bombay','mumbai') THEN 'Mumbai'
    WHEN customer_city IN ('madras','chennai') THEN 'Chennai'
    WHEN customer_city IN ('poona','pune') THEN 'Pune'
    WHEN customer_city IN ('calcutta','kolkata') THEN 'Kolkata'
    WHEN customer_city IN ('ahmdabad','ahmedabad') THEN 'Ahmedabad'
    WHEN customer_city IN ('hyderbad','hyderabad') THEN 'Hyderabad'
	ELSE INITCAP(customer_city)
END;	

-- 4. Payment Method Clean

UPDATE staging_orders
SET payment_method = CASE
    WHEN payment_method IN ('credit card','card') THEN 'CARD'
    WHEN payment_method IN ('cod','cash on delivery') THEN 'COD'
    WHEN payment_method IN ('upi') THEN 'UPI'
    ELSE UPPER(payment_method)
END;	

-- 5. Delivery Status Clean

UPDATE staging_orders
SET delivery_status = CASE 
    WHEN delivery_status = 'delivered' THEN 'Delivered'
    WHEN delivery_status = 'cancelled' THEN 'Cancelled'
	ELSE INITCAP(delivery_status)
END;	

-- 6. Missing Values Handle

UPDATE staging_orders
SET customer_email = 'unknown@gmail.com'
WHERE customer_email IS NULL
   OR TRIM(customer_email) = ''
   OR customer_email NOT LIKE '%@%.%';

UPDATE staging_orders
SET customer_phone = '0'
WHERE customer_phone IS NULL OR customer_phone = '';

UPDATE staging_orders
SET rating = '3'
WHERE rating IS NULL OR rating = '';


UPDATE staging_orders
SET review_comment = 'NO review'
WHERE review_comment IS NULL OR review_comment = '';

-- 7. Date Fix (string → date)

UPDATE staging_orders
SET order_date = TO_DATE(order_date, 'DD-MM-YYYY');

-- 8. Multi-value Columns

SELECT 
    order_id,
	UNNEST(STRING_TO_ARRAY(product_name, ',')) AS product
FROM staging_orders;

SELECT 
    order_id,
    UNNEST(STRING_TO_ARRAY(category, ',')) AS category
FROM staging_orders;

-- 9. datatype
ALTER TABLE staging_orders
ALTER COLUMN unit_price TYPE FLOAT USING unit_price::FLOAT,
ALTER COLUMN quantity TYPE INT USING quantity::INT,
ALTER COLUMN discount_pct TYPE FLOAT USING discount_pct::FLOAT,
ALTER COLUMN total_amount TYPE FLOAT USING total_amount::FLOAT,
ALTER COLUMN rating TYPE FLOAT USING rating::FLOAT;

CREATE TABLE clean_orders AS 
SELECT *
FROM staging_orders;

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

-- analysis + insights
-- STEP 1: Business Overview (KPI)

SELECT 
   SUM(total_amount) AS Total_Revenue,
   COUNT(DISTINCT order_id) AS Total_Orders,
   ROUND(AVG(total_amount)::numeric, 2) AS Avg_order_values
FROM clean_orders;   

-- STEP 2: Category Performance

SELECT category,
      SUM(total_amount) AS Revenue
FROM clean_orders
GROUP BY category
ORDER BY Revenue DESC;

-- STEP 3: Monthly Trend

SELECT
    DATE_TRUNC('month', TO_DATE(order_date, 'YYYY-MM-DD')) AS month,
    COUNT(*) AS total_orders
FROM clean_orders
GROUP BY month
ORDER BY month;

-- STEP 4: Top Products

SELECT 
    product_name,
	SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY product_name
ORDER BY revenue DESC;
	
-- STEP 5: Customer Analysis

SELECT customer_name,
      SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY customer_name
ORDER BY revenue DESC;


-- STEP 6: Payment Method

SELECT payment_method,
    COUNT(*) AS Orders,
	SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY payment_method;
	
-- STEP 7: Delivery Performance

SELECT delivery_status,
      COUNT(*) AS Orders 
FROM clean_orders
GROUP BY delivery_status;

-- STEP 8: Rating Analysis

SELECT
    ROUND(AVG(rating)::numeric, 2) AS avg_rating
FROM clean_orders;

-- STEP 9:(MoM Growth)

WITH monthly AS(
    DATE_TRUNC('month', TO_DATE(order_date, 'DD-MM-YYYY')) AS month,
    SUM(total_amount) AS revenue
FROM clean_orders	
	
)
SELECT 
   month,
   Revenue,
   LAG(Revenue) OVER (ORDER BY month) AS per_month,
   ROUND(
           (Revenue - LAG(Revenue) OVER (ORDER BY month)) * 100/ 
		   LAG(Revenue) OVER (ORDER BY month), 2
   ) AS growth_pct
FROM monthly;   
   

-- STEP 10: Cohort Analysis

WITH first_order AS(
      SELECT customer_name,
	  MIN(order_date::date) AS first_date
	  FROM clean_orders
	  GROUP BY customer_name 
)
SELECT
 DATE_TRUNC('month', first_date) AS cohort_month,
 COUNT(customer_name) AS customer
 FROM first_order
 GROUP BY DATE_TRUNC('month', first_date)
 ORDER BY cohort_month;


-- STEP 11: Revenue Contribution % (Pareto Analysis)
 
WITH revenue_calc AS (
    SELECT product_name,
           SUM(total_amount) AS revenue
    FROM clean_orders
    GROUP BY product_name
),
total AS (
    SELECT SUM(revenue) AS total_revenue FROM revenue_calc
)

SELECT 
    product_name,
    revenue,
    ROUND((revenue * 100.0 / total.total_revenue)::numeric, 2) AS contribution_pct
FROM revenue_calc, total
ORDER BY revenue DESC;


-- STEP 12: Customer Segmentation (High / Medium / Low)

WITH customer_spend AS (
    SELECT customer_name,
           SUM(total_amount) AS total_spent
    FROM clean_orders
    GROUP BY customer_name
)

SELECT 
    customer_name,
    total_spent,
    CASE
        WHEN total_spent > 4000000 THEN 'High Value'
        WHEN total_spent BETWEEN 30000 AND 800000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS segment
FROM customer_spend;


-- STEP 13: Running Total

SELECT 
    order_date,
	SUM(total_amount) OVER (ORDER BY order_date) AS Running_total
FROM clean_orders;	
	
-- STEP 14: Basket Size Analysis

SELECT 
    order_id,
    COUNT(product_name) AS items_count
FROM clean_orders
GROUP BY order_id
ORDER BY items_count DESC;

-- STEP 15: Top City Performance

SELECT customer_city,
      SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY customer_city
ORDER BY revenue DESC;


 -- Spelling Fix-------------------------------

UPDATE clean_orders
SET customer_city = 'Unknown'
WHERE customer_city IS NULL OR customer_city = '';

UPDATE clean_orders
SET customer_city = CASE
    WHEN customer_city IN('banglore','bangalore','bengaluru','Banglore','Bengaluru') THEN 'Bangalore'
    WHEN customer_city IN ('bombay','mumbai','Bombay') THEN 'Mumbai'
    WHEN customer_city IN ('madras','chennai','Madras') THEN 'Chennai'
    WHEN customer_city IN ('poona','pune','Poona') THEN 'Pune'
    WHEN customer_city IN ('calcutta','kolkata','Calcutta') THEN 'Kolkata'
    WHEN customer_city IN ('ahmdabad','ahmedabad','Ahmdabad') THEN 'Ahmedabad'
    WHEN customer_city IN ('hyderbad','hyderabad','Hyderbad') THEN 'Hyderabad'
	ELSE INITCAP(customer_city)
END;

-- STEP 16: Churn Risk Analysis

SELECT customer_name
FROM clean_orders
GROUP BY customer_name
HAVING COUNT(order_id) = 1;

SELECT
    customer_name,
    SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY customer_name
HAVING SUM(total_amount) > 500;

-- STEP 17: Payment Success Strategy
SELECT 
    payment_method,
	AVG(total_amount) AS Avg_order_value
FROM clean_orders
GROUP BY  payment_method;

-- STEP 18: Rating Impact on Revenue

SELECT rating,
SUM(total_amount) AS revenue
FROM clean_orders
GROUP BY rating
ORDER BY rating;

-- STEP 19. Advanced Window Function

SELECT 
    order_id,
    TRIM(UNNEST(STRING_TO_ARRAY(product_name, ','))) AS product
FROM clean_orders;


SELECT 
    order_id,
    TRIM(UNNEST(STRING_TO_ARRAY(category, ','))) AS category
FROM clean_orders;

SELECT * 
FROM(
       SELECT 
	   category,
	   product_name,
	   SUM(total_amount) AS revenue,
	   RANK() OVER (PARTITION BY category ORDER BY SUM(total_amount) DESC) AS rnk
FROM clean_orders
GROUP BY category, product_name	  
)t
WHERE rnk = 1;


SELECT 
    order_id,
    TRIM(p.product) AS product_name,
    TRIM(c.category) AS category,
    total_amount
FROM clean_orders,
LATERAL UNNEST(STRING_TO_ARRAY(product_name, ',')) AS p(product),
LATERAL UNNEST(STRING_TO_ARRAY(category, ',')) AS c(category);








