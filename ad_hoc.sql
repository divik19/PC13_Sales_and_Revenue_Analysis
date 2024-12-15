-- 1. City-Level Fare and Trip Summary Report

SELECT 
    dc.city_name,
    COUNT(trip_id) AS total_trips,
    ROUND(AVG(fare_amount / distance_travelled_km),2) AS avg_fare_per_km,
    ROUND(AVG(fare_amount),2) AS avg_fare_per_trip,
    CONCAT(ROUND( (100 * COUNT(trip_id) / 
				  (SELECT COUNT(*) FROM fact_trips)), 2), '%') AS '%_contribution_to_total_trips'
FROM
    fact_trips ft
INNER JOIN
    dim_city dc USING (city_id)
GROUP BY dc.city_name
ORDER BY total_trips DESC;

-- 2. Monthly City-Level Trips Target Performance Report


with cte as (
	select
		dc.city_id as city_id,
		dc.city_name as city_name,
		date_format(ft.date, '%M') as month_name,
		count(trip_id) as actual_trips
	from fact_trips ft 
	inner join dim_city dc
	using (city_id)
	group by dc.city_id, dc.city_name, date_format(ft.date, '%M')
), cte2 as ( 
	select
		cte.city_name,
		cte.month_name,
		cte.actual_trips,
		mtt.total_target_trips as target_trips
	from cte
	inner join ( select *, date_format(month, '%M') as month_name from  targets_db.monthly_target_trips ) mtt
	on cte.city_id = mtt.city_id
    and cte.month_name = mtt.month_name
)
select 
	*,
    case 
		when actual_trips > target_trips then "Above Target"
        else "Below Target"
	end as performance_status,
    concat(round((actual_trips - target_trips)/ target_trips*100,2), '%') as '%_difference'
from cte2;

-- 3. City-Level Repeat Passenger Trip Frequemcy Report

select 
	city_name,
    concat(sum(case when trip_count = '2-Trips' then per_diff else 0 end), '%') as '2-Trips',
    concat(sum(case when trip_count = '3-Trips' then per_diff else 0 end), '%') as '3-Trips',
    concat(sum(case when trip_count = '4-Trips' then per_diff else 0 end),'%') as '4-Trips',
    concat(sum(case when trip_count = '5-Trips' then per_diff else 0 end),'%') as '5-Trips',
    concat(sum(case when trip_count = '6-Trips' then per_diff else 0 end),'%') as '6-Trips',
    concat(sum(case when trip_count = '7-Trips' then per_diff else 0 end),'%') as '7-Trips',
    concat(sum(case when trip_count = '8-Trips' then per_diff else 0 end),'%') as '8-Trips',
    concat(sum(case when trip_count = '9-Trips' then per_diff else 0 end),'%') as '9-Trips',
    concat(sum(case when trip_count = '10-Trips' then per_diff else 0 end),'%') as '10-Trips'
from (
select distinct
	dc.city_name as city_name,
    drtd.trip_count,
    round( 100*sum(drtd.repeat_passenger_count) over (partition by dc.city_name,drtd.trip_count order by dc.city_name) / 
			sum(drtd.repeat_passenger_count) over (partition by dc.city_name order by dc.city_name), 2) as per_diff
from dim_city dc
inner join dim_repeat_trip_distribution drtd
using (city_id)
) t 
group by city_name;

-- 4. Top and Bottom 3 City with Highest and Lowest Newest Passengers

select 
	city_name,
    total_new_passengers,
    case 
		when ranks < 4 then 'top_3' 
        when ranks > 7 then 'bottom_3'
        else null
	end as city_category
from (
select 
	dc.city_name as city_name,
    sum(new_passengers) as total_new_passengers,
    rank() over (order by sum(new_passengers) desc) as ranks
from dim_city dc
inner join fact_passenger_summary fps
using (city_id)
group by dc.city_name
) t
group by city_name
having city_category is not null;

-- 5. Month with Highest Revenue For Each City

with cte as (
	select distinct
	dc.city_name as city_name,
    date_format(ft.date, '%M') as highest_revenue_month,
    sum(ft.fare_amount) over (partition by dc.city_name, date_format(ft.date, '%M') order by dc.city_name ) as city_month_rev,
    sum(ft.fare_amount) over (partition by dc.city_name order by dc.city_name ) as city_rev
from dim_city dc
inner join fact_trips ft
using (city_id)
), cte2 as (
select 
	city_name,
    highest_revenue_month,
    city_month_rev as revenue,
    concat(round(100*city_month_rev/city_rev,2), '%') as percentage_contribution,
    row_number() over (partition by city_name order by city_month_rev desc) as  row_num
from cte 
)
select 
	city_name,
    highest_revenue_month,
    revenue,
    percentage_contribution
from cte2 
where row_num = 1 
order by percentage_contribution desc;


-- 6. Repeat Passenger Rate Analysis 

WITH city_aggregates AS (
    SELECT
        city_id,
        SUM(repeat_passengers) AS total_repeat_passengers,
        SUM(total_passengers) AS total_passengers
    FROM
        fact_passenger_summary
    GROUP BY
        city_id
)
SELECT
    dc.city_name,
    date_format(fps.month, '%M') as Month_name,
    fps.total_passengers,
    fps.repeat_passengers,
    ROUND((fps.repeat_passengers * 100.0 / fps.total_passengers), 2) AS monthly_repeat_passenger_rate,
    ROUND((ca.total_repeat_passengers * 100.0 / ca.total_passengers), 2) AS city_repeat_passenger_rate
FROM fact_passenger_summary fps
INNER JOIN city_aggregates ca
ON fps.city_id = ca.city_id
INNER JOIN dim_city dc
on dc.city_id = fps.city_id
ORDER BY fps.city_id, date_format(fps.month, '%M');
