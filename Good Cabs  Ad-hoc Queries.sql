-- 1. City_level_fare and Trip Summary Report

With Total_trips AS(
	SELECT COUNT(trip_id) AS total_trips_all
    FROM fact_trips
)
SELECT
	c.city_name, 
    COUNT(ft.trip_id) AS total_trips,
    ROUND(AVG(ft.fare_amount / NULLIF(ft.distance_travelled_km, 0)), 2) AS avg_fare_per_km, 
    ROUND(AVG(ft.fare_amount), 2) AS avg_fare_per_trip, 
    ROUND((COUNT(ft.trip_id) * 100.0) / total_trips_all, 2) AS percentage_contribution_to_total_trips
FROM  fact_trips ft
JOIN  dim_city c ON ft.city_id = c.city_id
JOIN  Total_trips tt
GROUP BY city_name, total_trips_all
ORDER BY total_trips DESC;

-- 2.Monthly City-Level Trips Target Performance Report

With trips AS (
	SELECT ft.city_id, c.city_name, 
		MONTH(ft.date) AS t_month_num,
		MONTHNAME(ft.date) AS month,
		ft.trip_id
FROM fact_trips ft
JOIN dim_city c ON ft.city_id = c.city_id
)
SELECT trips.city_name, trips.month, 
	   COUNT(trips.trip_id) AS actual_trips,
       ta.total_target_trips AS target_trips,
       CASE 
			WHEN COUNT(trips.trip_id) >= ta.total_target_trips THEN "Above Target"
            ELSE "Below Target"
	   END AS performance_status,
	   CONCAT(ROUND(((COUNT(trips.trip_id) - ta.total_target_trips) / ta.total_target_trips) * 100, 2), '%') AS percent_difference
FROM trips
		JOIN targets_db.monthly_target_trips ta 
		ON trips.city_id = ta.city_id  AND
        trips.month = MONTHNAME(ta.month)
GROUP BY trips.city_name, trips.month, trips.t_month_num, ta.city_id, ta.total_target_trips
ORDER BY trips.city_name, trips.t_month_num; 

-- 3. City_Level Repeat Passenger_Frequency Report

WITH RepeatedPassenger AS (
SELECT
	city_id, trip_count, SUM(repeat_passenger_count) as total_RP
FROM dim_repeat_trip_distribution r
GROUP BY city_id, trip_count
),
RepeatedPercentContribution AS(
SELECT city_id, trip_count, total_RP, SUM(total_RP) OVER (PARTITION BY city_id) AS total_city_RP,
	   CONCAT(CONVERT((total_RP / SUM(total_RP) OVER (PARTITION BY city_id)) * 100, DECIMAL(6,2)), '%')  AS p_contribution_pct
FROM RepeatedPassenger 
GROUP BY city_id, trip_count)
 SELECT 
	  city_name,
      MAX(CASE WHEN trip_count = "2-trips" THEN p_contribution_pct ELSE 0 END) AS '2-trips',
	  MAX(CASE WHEN trip_count = "3-trips" THEN p_contribution_pct ELSE 0 END) AS '3-trips',
      MAX(CASE WHEN trip_count = "4-trips" THEN p_contribution_pct ELSE 0 END) AS '4-trips',
	  MAX(CASE WHEN trip_count = "5-trips" THEN p_contribution_pct ELSE 0 END) AS '5-trips',
      MAX(CASE WHEN trip_count = "6-trips" THEN p_contribution_pct ELSE 0 END) AS '6-trips',
      MAX(CASE WHEN trip_count = "7-trips" THEN p_contribution_pct ELSE 0 END) AS '7-trips',
      MAX(CASE WHEN trip_count = "8-trips" THEN p_contribution_pct ELSE 0 END) AS '8-trips',
      MAX(CASE WHEN trip_count = "9-trips" THEN p_contribution_pct ELSE 0 END) AS '9-trips',
	  MAX(CASE WHEN trip_count = "10-trips" THEN p_contribution_pct ELSE 0 END) AS '10-trips'
FROM RepeatedPercentContribution
JOIN dim_city  ON RepeatedPercentContribution.city_id = dim_city.city_id
GROUP BY city_name;

-- 4.Cities with highest and lowest total new passengers

WITH RankedCities AS (
    SELECT 
        c.city_name,
        SUM(f.new_passengers) AS Total_New_Passengers,
        RANK() OVER (ORDER BY SUM(f.new_passengers) DESC) AS Ranking
    FROM fact_passenger_summary f
    JOIN dim_city c ON f.city_id = c.city_id
    GROUP BY c.city_name
),
CategorizedCities AS (
    SELECT  
        city_name, 
        Total_New_Passengers, 
        Ranking,
        CASE 
            WHEN Ranking <= 3 THEN 'Top 3'
            WHEN Ranking >= 8 THEN 'Bottom 3'
            ELSE 'Middle'
        END AS Category
    FROM RankedCities
)
SELECT 
    city_name, 
    Total_New_Passengers, 
    Ranking, 
    Category
FROM CategorizedCities
WHERE Category IN ('Top 3', 'Bottom 3'); 


-- 5. Identify Months WITH HIGHEST REVENUE FOR EACH MONTHS

WITH MonthlyRevenue AS (
    SELECT 
        city_id, 
        MONTHNAME(date) AS month_name, 
        SUM(fare_amount) AS total_revenue
    FROM 
        fact_trips
    GROUP BY 
        city_id, MONTHNAME(date)
),
RevenueWithMax AS (
    SELECT 
        r.city_id, 
        c.city_name, 
        r.month_name, 
        r.total_revenue,
        MAX(r.total_revenue) OVER (PARTITION BY r.city_id) AS max_revenue,
        SUM(r.total_revenue) OVER (PARTITION BY r.city_id) AS city_total_revenue
    FROM 
        MonthlyRevenue r
    JOIN 
        dim_city c 
    ON 
        r.city_id = c.city_id
)
SELECT 
    city_name, 
    month_name AS highest_revenue_month, 
    max_revenue AS revenue, 
    CONCAT(ROUND((max_revenue / city_total_revenue) * 100, 2), '%') AS contribution_pct
FROM 
    RevenueWithMax
WHERE 
    total_revenue = max_revenue;
    
-- 6.(i) Month Repeat Passenger Rate Analysis
WITH MonthlyRepeatRate AS (
    SELECT 
        d.city_name,
        MONTHNAME(f.month) AS month_name,
        SUM(f.total_passengers) AS total_passengers,
        SUM(f.repeat_passengers) AS repeat_passengers
    FROM 
        fact_passenger_summary f
    JOIN 
        dim_city d 
    ON 
        f.city_id = d.city_id
    GROUP BY 
        d.city_name, MONTHNAME(f.month)
)
SELECT 
    city_name,
    month_name AS Month,
    total_passengers,
    repeat_passengers,
    CONCAT(ROUND((repeat_passengers / total_passengers) * 100, 2), '%') AS Monthly_Repeat_Passenger_Rate
FROM 
    MonthlyRepeatRate;
    
-- 6.City Repeat Passenger Rate Analysis
SELECT 
    c.city_name,
    CONCAT(ROUND(SUM(repeat_passengers / total_passengers) * 100, 2), '%') AS Overall_Repeat_Passenger_Rate
FROM 
    fact_passenger_summary f
JOIN 
	dim_city c
ON f.city_id = c.city_id
GROUP BY c.city_name
ORDER BY Overall_Repeat_Passenger_Rate DESC;

    




	
        
        

