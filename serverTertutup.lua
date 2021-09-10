time = require "time"
uuid = require "uuid"

box.cfg{
    listen = '127.0.0.1:3301'
}

queue = require "queue"
queue.start()
box.queue = queue

--box.schema.user.grant('guest', 'read,write,execute', 'universe')
--box.schema.user.grant('guest', 'create','space')
--box.schema.user.grant('guest', 'write', 'space', '_schema')
--box.schema.user.grant('guest', 'write', 'space', '_space')

-- -- Create database ParkData with SQL (Done)
-- Create tube for park queue
park_tube = queue.create_tube("park_tube", "fifottl", {if_not_exists = true})

--Parking Function

--A.Create function to generate ticket id
--Using uuid module

--B. Create function to determine base price
function check_vehicle(v)
    if(v == 'motorcycle')
    then
        base = 2000
        return base
    else
        base = 4000
        return base
    end
end

-- C. Create Ticket Method
function create_ticket(vehicle)
    -- Record time in
    local our_time_in = time.nowlocal()
    local time_in = tostring(our_time_in)

    --Create ticket_id
    local ticket_id = tostring(uuid())

    --Determine base price
    local price = check_vehicle(vehicle)

    print("Your ticket_id: " .. ticket_id)
    return park_tube:put({ type = 1, ticket_id = ticket_id, time_check_in = time_in, base_price = price },{ttl = 60})
end

-- D. Remote Call: check_in() function
function check_in(ticket_id, time_check_in,base_price)
    --INSERT data into SQL
    sql_statement = "INSERT INTO ParkData (ticket_id, check_in, base_price) VALUES ('".. ticket_id .."','"..time_check_in .."', ".. base_price .. ");"
    box.execute(sql_statement)
end

-- E. Function to select time_in
function select_time_in(ticket_id)
    select_statement = "SELECT check_in FROM ParkData WHERE ticket_id='".. ticket_id .."';"
    data_in = box.execute(select_statement)

    return data_in.rows
end

-- F. Function to select base price
function select_bprice(ticket_id)
    select_statement = "SELECT base_price FROM ParkData WHERE ticket_id = '"..ticket_id.."';"
    data_in = box.execute(select_statement)
    data_in = data_in.rows
    data_in = data_in[1]
    data_in = tostring(data_in)

    -- Cleaning data
    cleaned_data = data_in:gsub(('%]'), '')
    cleaned_data = cleaned_data:gsub(('%['), '')
    cleaned_data = tonumber(cleaned_data)

    return cleaned_data
end

-- G. Local function to clean and return data
function clean_text(text)
    local sub = text:gsub('%]', '')
    local sub = sub:gsub(('%['), '')
    return sub
end

-- H. Function to select time from ticket id and clean it with python also as check out request
function clean_time_string(ticket_id)
    --SELECT data from ParkData
    local time_check_in = select_time_in(ticket_id)
    local time_check_in = tostring(time_check_in[1])
    local clean_time_in = clean_text(time_check_in)

    -- Put task to call check out function with cleaned time
    -- Send to python to clean unnecessary quote to also served as check out request - type 2

    return park_tube:put({ type = 2, ticket_id = ticket_id, text = clean_time_in }, {ttl = 60})
end

-- I. Remote call: check_out() function
function check_out(ticket_id, time_check_in)
    -- Record time_out
    local time_out = time.nowlocal()
    local time_out_str = tostring(time_out)
    print("User check out time: ".. time_out_str)
    -- Select base_price
    local base_price = select_bprice(ticket_id)

    -- Calculate duration
    -- Change from str to datetime
    local datetime_in = time.todate(time_check_in)
    local duration = time_out - datetime_in

    local duration_hours = duration:hours()
    local duration_minutes = duration:minutes()
    local duration_to_minutes = (duration_hours * 60) + duration_minutes
    print("Total duration in minutes:" .. duration_to_minutes)

    -- Calculate total payment
    local calculation_total = duration_to_minutes / 60 * base_price
    -- Round total payment
    local calculation_total = math.floor(calculation_total)

    print("Total payment: " .. calculation_total)

    -- Update SQL
    update_statement = "UPDATE ParkData SET check_out='".. time_out_str .."', duration=".. duration_to_minutes ..", total_payment =".. calculation_total .." WHERE ticket_id='".. ticket_id .."';"
    box.execute(update_statement)

    --Put task
    return park_tube:put({ type = 3, ticket_id = ticket_id, total_payment = calculation_total}, { ttl = 60 })
end

-- J. Function to save payment id
function save_payment_id(ticket_id, trx_id, qr_link)
    --print statement
    print("Midtrans transaction ID: " .. trx_id)
    print('Qr code link:' .. qr_link)
    -- Update SQL
    update_statement = "UPDATE ParkData SET payment_id='".. trx_id .. "' WHERE ticket_id='".. ticket_id .. "';"
    box.execute(update_statement)
end

-- K. Confirm Payment
function confirm_pay(order_id)
    return park_tube:put({ type = 4, order_id = order_id }, { ttl = 60 })
end




