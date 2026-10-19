local root=assert(os.getenv("CLINGY_TEST_ROOT"))
package.path=root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
local c=require("clingy")
local v=require("valua")
local app=c.create({name="windows",root=c.node({
  c.option({key="value",aliases={"--value"},value={schema=v.string()}}),
  c.flag({key="verbose",aliases={"-v","--verbose"}}),
})})
local parsed=app:parse({"--value","space ü","-v"})
assert(parsed.args.value=="space ü" and parsed.args.verbose)
assert(app:help():find("--value",1,true))
local process=require("clingy.process").spawn({argv={"cmd.exe","/d","/c","exit","17"},mode="inherit"})
assert(process:wait()==17,"managed process lost its exit status")
print("PASS: Windows declarations, validated options, help and managed exit status")
