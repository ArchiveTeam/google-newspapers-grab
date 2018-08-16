dofile("urlcode.lua")
dofile("table_show.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local ids = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local nid, dat = string.match(item_value, "^([^;]+);([^;]+)$")
local page_data = nil

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  return true
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(url, "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
       and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end
  
  if allowed(url, nil) then
    html = read_file(file)
    if string.match(url, "^https?://news%.google%.com/newspapers%?nid=[^&]+&dat=[0-9]+&printsec=frontpage$") and page_data == nil then
      page_data = load_json_file(string.match(html, '_OC_Run%(({"page":%s*%[[^%]]+%],%s*"prefix":%s*"[^"]+"})'))
      for _, page in pairs(page_data["page"]) do
        check(page_data["prefix"] .. "&pg=" .. page["pid"] .. "&jscmd=click3")
      end
    end
    if string.match(url, "&jscmd=click3$") then
      local data = load_json_file(html)
      local pid = string.match(url, "&pg=([^&]+)")
      local tileres = data["page"][1]["additional_info"]["[NewspaperJSONPageInfo]"]["tileres"]
      tileres = tileres[#tileres]
      for i=0,math.floor(tileres["h"]/256+1)*math.floor(tileres["w"]/256+1) do
        check(page_data["prefix"] .. "&pg=" .. pid .. "&img=1&hl=en&zoom=" .. tileres["z"] .. "&tid=" .. i)
      end
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end

  if status_code ~= 200 or string.match(url["url"], "/sorry/") then
    return wget.actions.ABORT
  end

  os.execute("sleep 0.5")

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
