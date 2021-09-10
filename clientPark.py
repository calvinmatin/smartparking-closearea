#!/usr/bin/env python3
import asyncio
from typing import Text
import asynctnt
import asynctnt_queue
import parkmodule

async def run():
    conn_queue =  asynctnt.Connection(host='127.0.0.1', port='3301')

    await conn_queue.connect()
    
    queue = asynctnt_queue.Queue(conn_queue)
    park_tube = queue.tube('park_tube')

    while True:
        #Retrieve a task from queue
        task = await park_tube.take(1)

        if task:
            #Call check-in function & save data to tarantool db
            if task.data['type'] == 1:
                #... do some work with task
                print('Task data (check-in): {}'.format(task.data))
                #Remote call funciton - call check-in() function from queue server
                work = await conn_queue.call('check_in', [task.data['ticket_id'], task.data['time_check_in'], task.data['base_price']])

                #call check-out function
            elif task.data['type'] == 2:
                #... do some work qith task
                print('Task data (check-out/cleaning): {}'.format(task.data))
                text = task.data['text']
                text_cleaning = parkmodule.totally_clean_text(text)
                #Testing cleaned data
                work = await conn_queue.call('test_clean_id', [text_cleaning])
                work = await conn_queue.call('check_out', [task.data['ticket_id'], text_cleaning])
            elif task.data['type'] == 3:
                #...do some work with task
                print('Task data (create bill payment): {}'.format(task.data))
                # Create payment with midtrans API
                create_bill = parkmodule.create_payment(task.data['ticket_id'], task.data['total_payment'])
                qr_link = parkmodule.create_qr_link(create_bill)
                trx_id_get = parkmodule.get_trx_id(create_bill)
                work = await conn_queue.call('save_payment_id', [task.data['ticket_id'], trx_id_get, qr_link])

            elif task.data['type'] == 4:
                # ... do some work with task
                print('Task data (check status payment): {}'.format(task.data))
                #Create payment with midtrans API
                check_payment = parkmodule.get_status(task.data['order_id'])

                await task.ack()
                print('Task status: {}'.format(task.status))

                #await conn_queue.disconnect()
                # await conn_auth.disconnect()

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())
        loop.close()