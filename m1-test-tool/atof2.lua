box.cfg{}
--box.execute('set session "sql_vdbe_debug" = true;')
for i = 1, 261  do
    local pow = math.random(100)
    x = math.pow((math.random()-0.5)*2*math.random(), pow)
end

print(x)
str = tostring(x)
print(str)
box.sql_atof(str)
