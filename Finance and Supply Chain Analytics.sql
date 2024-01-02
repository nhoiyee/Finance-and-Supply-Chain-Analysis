-- Finance and Supply Chain Analytics

-- Finance Analytics

# create a function for fiscal year

CREATE FUNCTION `get_fiscal_year` (
CALENDAR_DATE DATE
) 
RETURNS integer
deterministic
BEGIN
declare fiscal_year int;
set fiscal_year= year(date_add( CALENDAR_DATE, interval 4 month));
RETURN fiscal_year;
END
# create a function for fiscal quarter
CREATE DEFINER=`root`@`localhost` FUNCTION `get_fiscal_month`(
CALENDAR_DATE DATE
) RETURNS char(2) CHARSET utf8mb4
    DETERMINISTIC
BEGIN

	declare m tinyint;
	declare qtr char(2);
	set m= month(CALENDAR_DATE);

case
when m in (9,10,11) then
set qtr="Q1";
when m in (12,1,2) then
set qtr="Q2";
when m in (3,4,5) then
set qtr="Q3";
	else
set qtr="Q4";

end case;
RETURN qtr;
END

# Gross Sales Report 1: Monthly Product Transactions for Croma Customer in FY 21

SELECT 
s.date, s.product_code,
p.product, p.variant, s.sold_quantity , g.gross_price,
round(g.gross_price* s.sold_quantity,2) as gross_price_total

FROM fact_sales_monthly s
join dim_product p
on p.product_code=s.product_code
join fact_gross_price g

on g.product_code =s.product_code and 
g.fiscal_year=get_fiscal_year(s.date)
where
customer_code=90002002 and
get_fiscal_year(date)=2021
order by date asc
limit 100000000
# Gross Sales Report 2: Monthly Product Transactions for all FY

begin
select
s.date, sum(round(s.sold_quantity*g.gross_price,2)) as monthly_sales
FROM fact_sales_monthly s
join fact_gross_price g
on g.fiscal_year= get_fiscal_year(s.date)
and g.product_code=s.product_code
where customer_code =90002002
group by date;
end

# Generate Monthly Gross Sales Report for any customer using stored procedure

	CREATE PROCEDURE `get_monthly_gross_sales_for_customer`(
        	in_customer_codes TEXT
	)
	BEGIN
        	SELECT 
                    s.date, 
                    SUM(ROUND(s.sold_quantity*g.gross_price,2)) as monthly_sales
        	FROM fact_sales_monthly s
        	JOIN fact_gross_price g
               	    ON g.fiscal_year=get_fiscal_year(s.date)
                    AND g.product_code=s.product_code
        	WHERE 
                    FIND_IN_SET(s.customer_code, in_customer_codes) > 0
        	GROUP BY s.date
        	ORDER BY s.date DESC;
	END
# Stored procedure for market badge (total sold quantity> 5 million = "Gold", else: "Silver"

procedure 'get_market_badge'(
in in_market varchar(45),
in in_fiscal_year year,
out out_badge varchar(45)
)
begin
declare qty int default 0;

if in_market="" then
set in_market="India";
end if;

select 
sum(sold_quantity) into qty
from fact_sales_monthly s
join dim_customer c
on s.customer_code=c.customer_code
where get_fiscal_year(s.date)= in_fiscal_year and
c.market=in_market
group by c.market;

#determine market badge

if qty > 500000 then
set out_badge="gold";
else 
set out_badge="silver";
end if;

end

-- Supply Chain Analytics 

# Creating table fact_act_est which contains sold_qty and forecast qty

create table fact_act_est
(
        	select 
                    s.date as date,
                    s.fiscal_year as fiscal_year,
                    s.product_code as product_code,
                    s.customer_code as customer_code,
                    s.sold_quantity as sold_quantity,
                    f.forecast_quantity as forecast_quantity
        	from 
                    fact_sales_monthly s
        	left join fact_forecast_monthly f 
        	using (date, customer_code, product_code)

union

        	select 
                    s.date as date,
                    s.fiscal_year as fiscal_year,
                    s.product_code as product_code,
                    s.customer_code as customer_code,
                    s.sold_quantity as sold_quantity,
                    f.forecast_quantity as forecast_quantity
        	from 
                    
fact_forecast_monthly f 
        	left join fact_sales_monthly s
        	using (date, customer_code, product_code)
);

# Forecast Accuracy Report 

with forecast_err_table as(
SELECT 
s.customer_code,
sum(s.sold_quantity) as total_sold_qty,
sum(s.forecast_quantity) as total_forecast_qty,
sum((forecast_quantity-sold_quantity)) as net_err,
sum((forecast_quantity-sold_quantity))*100/sum(forecast_quantity) as pct_net_err,
sum(abs(forecast_quantity-sold_quantity)) as abs_err,
sum(abs(forecast_quantity-sold_quantity))*100/sum(forecast_quantity) as abs_err_pct

FROM gdb0041.fact_act_est s
where s.fiscal_year=2021
group by customer_code)

select 
e.*,
c.customer,
c.market,
if (abs_err_pct>100,0,100-abs_err_pct) as forecast_accuracy
from forecast_err_table e
join dim_customer c
using(customer_code)
order by forecast_accuracy desc

# Forecast Accuracy 2020 vs 2021

set sql_mode="";
drop table if exists forecast_accuracy_2021;
create temporary table forecast_accuracy_2021
with forecast_err_table as
(
SELECT 
s.customer_code,
c.customer,
c.market,

sum(s.sold_quantity) as total_sold_qty,
sum(s.forecast_quantity) as total_forecast_qty,
sum((forecast_quantity-sold_quantity)) as net_err,
round(sum((forecast_quantity-sold_quantity))*100/sum(forecast_quantity),2) as pct_net_err,
sum(abs(forecast_quantity-sold_quantity)) as abs_err,
round(sum(abs(forecast_quantity-sold_quantity))*100/sum(forecast_quantity),2) as abs_err_pct

FROM gdb0041.fact_act_est s

join dim_customer c
on s.customer_code =c.customer_code
where s.fiscal_year=2021
group by customer_code
)
SELECT *,

if (abs_err_pct >100, 0,100-abs_err_pct) as forecast_accuracy
from forecast_err_table
order by forecast_accuracy desc;

drop table if exists forecast_accuracy_2020;
create temporary table forecast_accuracy_2020
with forecast_err_table as

(
select
s.customer_code,
c.customer,
c.market,

sum(s.sold_quantity) as total_sold_qty,
sum(s.forecast_quantity) as total_forecast_qty,
sum((forecast_quantity-sold_quantity)) as net_err,
round(sum((forecast_quantity-sold_quantity))*100/sum(forecast_quantity),2) as pct_net_err,
sum(abs(forecast_quantity-sold_quantity)) as abs_err,
round(sum(abs(forecast_quantity-sold_quantity))*100/sum(forecast_quantity),2) as abs_err_pct

FROM gdb0041.fact_act_est s

join dim_customer c
on s.customer_code =c.customer_code
where s.fiscal_year=2020
group by customer_code
)

select *,
if (abs_err_pct >100, 0,100-abs_err_pct) as forecast_accuracy
from forecast_err_table
order by forecast_accuracy desc;

select
f_2020.customer_code,
f_2020.customer,
f_2020.market,
f_2020.forecast_accuracy as forecast_accuracy_2020,
f_2021.forecast_accuracy as forecast_accuracy_2021


from forecast_accuracy_2020 f_2020
join forecast_accuracy_2021 f_2021
on f_2020.customer_code = f_2021.customer_code
where f_2021.forecast_accuracy < f_2020.forecast_accuracy
order by f_2020.forecast_accuracy desc
;