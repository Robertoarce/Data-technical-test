-- AGENDA

-- SET UP
-- DATA CHECK-UP
-- ANALYSIS


------------------------------
---------- SET UP ------------
------------------------------


DROP TABLE IF EXISTS yousign.subs;
DROP TABLE IF EXISTS yousign.calend_days;

-- Creation of Tables

CREATE TABLE yousign.subs
(
    "customer_id" character varying(65) COLLATE pg_catalog."default" NOT NULL,
    "subscription_id" character varying(65) COLLATE pg_catalog."default" NOT NULL,
    "plan_id" character varying(26) COLLATE pg_catalog."default" NOT NULL,
    "start_date" date NOT NULL,
    "end_date" date NOT NULL,
    "monthly_amount" numeric NOT NULL
)

TABLESPACE pg_default;

ALTER TABLE yousign.subs
    OWNER to postgres;
	
 
CREATE TABLE yousign.calend_days
(
    "date_day" date NOT NULL
)

TABLESPACE pg_default;

ALTER TABLE yousign.calend_days
    OWNER to postgres;

-- Import Data from CSV's

COPY yousign.subs FROM 'C:\Users\rober\ALL\04 Jobs\13 yousign\subscription_periods.csv' WITH (FORMAT csv , DELIMITER ",", HEADER);	
COPY yousign.calend_days FROM 'C:\Users\rober\ALL\04 Jobs\13 yousign\days.csv' WITH (FORMAT csv , DELIMITER ",", HEADER);	


-- Combining tables

select 
    *,

from
    yousign.subs as a
cross join 
    yousign.calend_days as b
    

------------------------------
---------- DATA CHECK-UP ----------
------------------------------

--  Valid data: no negative numbers on "Monthly_amount"
select * from yousign.subs
where  monthly_amount < 0 

-- Congruent Data: there is one start_date that is before end_date
with 

base as 

(
select
	row_number() over() as indexo,
	*,
	 end_date -start_date +1 as subs_days
	from
	yousign.subs
)

select * from base
where subs_days <1

------------------------------
---------- ANALYSIS ----------
------------------------------


-- QUESTION 3 

--- 1) How many customers churned during June 2020?

--AGENDA: 
-- 1) index customers and offers of users (for self check)
-- 2) limit calendar days (only june)
-- 3) cross users + calendar AND mark presence 
-- 4) Mark presence for each day, no matter the offer
-- 5) Add col with the starting counting point (min subscription date) AND last day (max subs date)
-- 6) Mark if is a stayer, non present or churner following the rules for each.
-- 7) count the total churners


with 

-- 1) index customers and offers of users (for self check)
base as 
(
select
	row_number() over() as indexo,
	dense_rank() over(order by customer_id ) as cust_index,
	*
	from
	yousign.subs
	
),
-- 2) limit calendar days (only june)
june_days as 
(
	select * from
		yousign.calend_days
	where 
		date_day >= '2020-05-31'
		and 
		date_day <= '2020-06-30'

),

-- 3) cross users + calendar AND mark presence 
present_by_offer_days as
(
	select 
		*,
		case when( start_date <= date_day and end_date >= date_day) then 1 else 0 end as presence
	from
		base as a
	cross join 
		june_days as b
),

-- 4) Mark presence for each day, no matter the offer
presence_by_day as 
(
	select 
		cust_index,
		customer_id,
		date_day,
		max(presence) as present

	from 
	present_by_offer_days
	group by cust_index, customer_id,date_day
	order by cust_index, date_day
)
 
-- 5) Add col with the starting counting point (min subscription date) AND last day (max subs date)
, present_min_max as 
(
	select 
	*,
	min(case when present =1 then date_day else null end) over (partition by customer_id) as min_presence,
	max(case when present =1 then date_day else null end) over (partition by customer_id) as max_presence
	from presence_by_day
)

-- 6) Mark if is a stayer, non present or churner following the rules for each.
, final_table as 
(
select 
	cust_index, customer_id, min_presence,max_presence,
	case when(min_presence is not NULL and max_presence = '2020-06-30') then 1 else 0 end as stayer, 
	case when(min_presence is not NULL and max_presence <> '2020-06-30') then 1 else 0 end as churner ,
	case when(min_presence is NULL)   then 1 else 0 end as not_present	
	
 
   from present_min_max
   
   group by cust_index, customer_id, min_presence,max_presence
   order by cust_index
)
 
-- 7) Count the total churners
select 
	sum(churner) as count_total_churners
	from 
	final_table



--- 2) What is the evolution of the churned amount (revenue loss) over 2020?

-- Agenda
-- 1) Inidex by user and month (for follow up)
-- 2) Cross with date table and get only days within 2020
-- 3) Mark presence for each day, no matter the offer
--	 branch point -->3b) get average day salary by month using user present days.
-- 4) Add col with the starting counting point (min subscription date) AND ending point (max subs date) by month
-- 5) Mark presence for each day, no matter the offer
-- 6) Count unpresent days within min  and  max date class it by month 
-- 7) Multiply avg salary per day x unpresent days
-- 8) sum revenue loss per month




with
-- 1) Index by user and month (for follow up)

point_1 as (
select 

dense_rank() over (order by customer_id) as cust_id,
row_number() over (partition by customer_id order by start_date) as offer_id,
*
from 
yousign.subs

)

-- 2) Cross with date table and get only days within 2020
,point_2 as (
select	
	*
from 
	point_1 as a 
cross join 
	yousign.calend_days as b
where 
	date_day >= '2020-01-01'
	and
	date_day < '2021-01-01'
)

-- 3) Mark presence for each day, no matter the offer
,point_3 as (

select 
	*,
	case when (start_date <= date_day and end_date >= date_day) then 1 else NULL end as day_offer_presence
	from point_2
)


--	 branch point 3) get average day salary by month using user present days.
,branch_point_3a as (

select 
	*,
	date_part('month',date_day) as calend_month,
	avg(case when day_offer_presence = 1 and monthly_amount>0 then monthly_amount else NULL end) 
	over(partition by cust_id, date_part('month',date_day)) as avg_month_salary
	from point_3
)

, branch_point_3b as (
select
	distinct cust_id,customer_id, calend_month, avg_month_salary
	from branch_point_3a 
	
)


-- 4) Add col with the starting counting point (min subscription date) AND ending point (max subs date) by month
,point_4 as(

	select 
	*,
	min(case when day_offer_presence =1 then date_day else null end) over (partition by customer_id, date_part('month',date_day)) as min_presence,
	max(case when day_offer_presence =1 then date_day else null end) over (partition by customer_id, date_part('month',date_day)) as max_presence
	
	from point_3
)
-- 5) Mark presence for each day, no matter the offer
,point_5 as (
	
select 
	  cust_id, customer_id, date_day, 
	min(min_presence) as min_presence,
	max(max_presence) as max_presence ,
	case when(min(min_presence) is not NULL and min(min_presence) <= date_day and max(max_presence) >= date_day) then 1 else 0 end as day_presence
	from 	
	point_4
	group by  cust_id, customer_id, date_day, min_presence , max_presence
	)
	
-- 6) Count unpresent days within min  and  max date class it by month 
,point_6 as (

	select distinct
		a.cust_id,
		a.customer_id,
		b.calend_month,
		b.avg_month_salary,
		
		sum (case when a.day_presence =1 then 0 else 1 end ) over(partition by a.customer_id, date_part('month',a.date_day)) as sum_month_absence_days
	from
		point_5  as a
	left join
		branch_point_3b as b
	on 
		a.customer_id = b.customer_id
	and 
		date_part('month',a.date_day)  =  b.calend_month 
)

-- 7) Multiply avg salary per day x unpresent days
,point_7 as (
	select 
		cust_id,customer_id,
		calend_month,
		avg_month_salary/30 *sum_month_absence_days as revenue_loss
	from 
		point_6
)

-- 8) sum revenue loss

 select 
	 calend_month,
	 sum(revenue_loss) as total_rev_loss
 
 from 
 	point_7
	
 group by
	calend_month
order by calend_month
 