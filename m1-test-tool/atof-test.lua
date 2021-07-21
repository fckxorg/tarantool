box.cfg{}
--box.execute('set session "sql_vdbe_debug" = true;')
for i = 1, 10000  do
    local pow = math.random(100)
    x = math.pow((math.random()-0.5)*2*math.random(), pow)
        local y = box.execute(string.format("SELECT %s=CAST(quote(%s) AS NUMBER)",x, x)) 
        if y['rows'][1][1] == false then  
                print(i)
		require('log').error(y.rows[1][1]) 
                os.exit()
        end
end
