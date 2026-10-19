-- A data-only transport for scripts; no cmd quoting or variable expansion.
local M = {}
function M.literal(value)
  assert(type(value) == "string" and not value:find("\0",1,true), "PowerShell literal must be a string without NUL")
  return "'" .. value:gsub("'", "''") .. "'"
end
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.command(script)
  local bytes, index = {}, 1
  local function unit(value)
    bytes[#bytes+1]=string.char(value%256,math.floor(value/256))
  end
  while index<=#script do
    local lead=script:byte(index); local point,count
    if lead<128 then point,count=lead,1
    elseif lead>=194 and lead<=223 then point,count=lead-192,2
    elseif lead>=224 and lead<=239 then point,count=lead-224,3
    elseif lead>=240 and lead<=244 then point,count=lead-240,4
    else error("invalid UTF-8 in PowerShell script") end
    for offset=1,count-1 do
      local continuation=script:byte(index+offset)
      assert(continuation and continuation>=128 and continuation<=191,"invalid UTF-8 continuation")
      point=point*64+continuation-128
    end
    assert(point<=1114111 and not(point>=55296 and point<=57343),"invalid Unicode scalar")
    if point<65536 then unit(point)
    else point=point-65536; unit(55296+math.floor(point/1024)); unit(56320+point%1024) end
    index=index+count
  end
  local raw=table.concat(bytes); local encoded={}
  for start=1,#raw,3 do
    local a,b,c=raw:byte(start,start+2)
    local value=a*65536+(b or 0)*256+(c or 0)
    encoded[#encoded+1]=alphabet:sub(math.floor(value/262144)%64+1,math.floor(value/262144)%64+1)
      .. alphabet:sub(math.floor(value/4096)%64+1,math.floor(value/4096)%64+1)
      .. (b and alphabet:sub(math.floor(value/64)%64+1,math.floor(value/64)%64+1) or "=")
      .. (c and alphabet:sub(value%64+1,value%64+1) or "=")
  end
  local result="powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand " .. table.concat(encoded)
  assert(#result<8000,"PowerShell command exceeds cmd limit; write a script file")
  return result
end
return M
