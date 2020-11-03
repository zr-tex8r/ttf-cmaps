program = 'togidcopy'
version = '0.1.0'
mod_date = '2020/10/31'
verbose = 0
in_file, out_file = nil
---------------------------------------- module "psyllium"
do
  psyllium = {}

  local lpeg = require 'lpeg'
  local C, Cs, Ct, P, R, S, V, pmatch =
    lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.match
  local assert, setmetatable, tonumber, tostring, type, floor =
    assert, setmetatable, tonumber, tostring, type, math.floor
  local insert, concat, unpack =
    table.insert, table.concat, unpack or table.unpack, math.f
  local byte, char, format, gsub, match, sub =
    string.byte, string.char, string.format, string.gsub, string.match,
    string.sub

  -- sub-parsers
  local decimal = S'+-'^-1 * (R'09'^0 * '.' * R'09'^0 - '.') *
      (S'eE' * S'+-'^-1 * R'09'^1)^-1 * -1
  local function parse_number(src)
    local b, v = match(src, '^(%d+)#([%d%a]+)$'); b = b and tonumber(b)
    if b and 2 <= b and b <= 36 then return tonumber(v, b) end
    if pmatch(decimal, src) then return tonumber(src) end
  end
  local function parse_lname(src)
    return sub(src, 2)
  end
  local p_escape = { n='\n'; r='\r'; t='\t'; b='\b'; f='\f' }
  local function parse_oct(s) return char(tonumber(s, 8) % 256) end
  local lstring = Cs((P'\\' / '' * (
    (R'07' * R'07'^-2) / parse_oct + S'nrtbf' / p_escape +
    (P'\r\n' + S'\r\n') / '' + C(1)
  ) + C((P(1) - '\\')^1))^0)
  local function parse_lstring(src)
    return assert(pmatch(lstring, sub(src, 2, -2)))
  end
  local function parse_xstring(src)
    src = gsub(sub(src, 2, -2), '%s+', '')
    if #src % 2 == 1 then src = src..'0' end
    return gsub(src, '..', function(x)
      return char(tonumber(x, 16))
    end)
  end

  -- token
  local function digest(src)
    src = src:gsub('%s', ' '):gsub('[^\32-\126]', '.')
    if #src > 60 then src = src:sub(1, 58)..'..' end
    return src
  end
  local token_meta = {
    __index = {};
    __tostring = function(self)
      local t, src = self.t, self.src
      if t == 'space' then return format("<space>[#=%d]", #src)
      else return format("<%s>%s", t, digest(src))
      end
    end;
  }
  local function make_token(t, src, v)
    return setmetatable({ t=t, src=src, v=v }, token_meta)
  end

  -- token generators
  local function gen_name(src)
    local nv = parse_number(src)
    if nv then return make_token('number', src, nv)
    else return make_token('name', src, src)
    end
  end
  local function gen_lname(src)
    return make_token('lname', src, parse_lname(src))
  end
  local function gen_lstring(src)
    return make_token('string', src, parse_lstring(src))
  end
  local function gen_xstring(src)
    return make_token('string', src, parse_xstring(src))
  end
  local function gen_t(t)
    return function(src) return make_token(t, src) end
  end
  local function gen_error(msg)
    return function(src) return make_token('error', src, msg) end
  end

  -- the grammar
  local any = P(1)
  local nl = P'\r\n' + S'\r\n'
  local ff = P'\f'
  local sp = S'\0\t\n\f\r '
  local delim = S'()<>[]{}/%'
  local delimT = S'[]{}'
  local reg = any - (sp + delim)
  local comment = P'%' * (any - S'\r\n\f')^0 * (nl + ff + -1)
  local lstringT = P{P'(' * ((any - S'\\()')^1 + P'\\' * any + V(1))^0 * ')'}
  local xstringT = P'<' * (R'09' + R'AF' + R'af' + '\n')^0 * '>'
  local nameT = reg^1
  local lnameT = P'/' * reg^0
  local token =
    sp^1 / gen_t('space') + comment / gen_t('comment') +
    lstringT / gen_lstring + xstringT / gen_xstring +
    lnameT / gen_lname + nameT / gen_name +
    delimT / gen_t('delim')
  local trap =
    (P'(' * any^0) / gen_error('malformed literal string') +
    (P'<' * any^0) / gen_error('malformed hex string') +
    any^1 / gen_error('unexpected character')
  local parser = Ct(token^0 * trap^-1)

  -- the parser
  function psyllium.parse(src)
    src = tostring(src)
    local parsed = pmatch(parser, src)
    if not parsed then return nil, "parser failure" end
    local last = parsed[#parsed]
    if last.t == 'error' then
      local s0 = gsub(sub(src, 1, #src - #last.src + 1), '\r\n?', '\n')
      local s1, s2 = gsub(s0, '[^\n]' ,''), gsub(s0, '.*\n', '')
      local m = "syntax error at line %d, char %d: %s"
      return nil, format(m, #s1 + 1, #s2, last.v)
    end
    return parsed
  end

  -- the formatter
  function psyllium.form(toks)
    local t = {}
    for i = 1, #toks do
      t[i] = (toks[i] and toks[i].src) or ''
    end
    return concat(t)
  end

  -- to set a new value
  local parser_nl = C((any - (nl * -1))^0) * C(nl^-1)
  local f_escape, c_digit = {}
  for k, v in pairs(p_escape) do f_escape[v] = '\\'..k end
  local function f_oct(c)
    return f_escape[c] or format('\\%03o', byte(c))
  end
  local lstringer = Cs((R'\0\31' / f_oct + C(1))^0)
  local function tostringx(v, b)
    local t, r = {}; v = (v <= 0) and 0 or floor(v)
    while v > 0 do
      r, v = v % b, floor(v / b)
      insert(t, 1, char(r + ((r < 10) and 48 or 87)))
    end
    return (#t == 0) and '0' or concat(t)
  end
  token_meta.__index.set = function(self, val)
    local t, src = self.t, self.src
    if t == 'comment' then
      val = tostring(val)
      if sub(val, 1, 1) ~= '%' then val = '%'..val end
      local v, n = pmatch(parser_nl, val)
      if n == '' then val, n = pmatch(parser_nl, src); val = v..n end
      self.src = val
    elseif t == 'string' then
      val = tostring(val)
      if sub(src, 1, 1) == '<' then
        src = '<'..gsub(val, '.', function(c)
          return format("%02x", byte(c))
        end)..'>'
      else
        local p = match('('..val..')', '^%b()$') and '[\\]' or '[\\()]'
        src = '('..assert(pmatch(lstringer, (gsub(val, p, '\\%0'))))..')'
      end
      self.src, self.v = src, val
    elseif t == 'lname' then
      val = tostring(val)
      if not pmatch(reg^1 * -1, val) then
        return nil, format("not a name: %s", val)
      end
      self.src, self.v = '/'..val, val
    elseif t == 'name' then
      val = tostring(val)
      if not pmatch(reg^1 * -1, val) then
        return nil, format("not a name: %s", val)
      end
      self.src, self.v = val, val
    elseif t == 'number' then
      local nsrc = nil
      if type(val) == 'string' then
        local v = parse_number(val)
        if v then nsrc, val = val, v end
      end
      if not nsrc then
        local v = tonumber(val)
        if not v then return nil, format("not a number: %s", val) end
        local b = match(src, '^(%d+)#')
        if b and floor(v) == v then
          nsrc, val = b..'#'..tostringx(v, tonumber(b)), v
        else nsrc = gsub(tostring(v), '%.0$', ''), v
        end
      end
      self.src, self.v = nsrc, val
    else return nil, format("cannot set to %s token", t)
    end
    return true
  end
end
---------------------------------------- logging
pcall(function()
  kpse = require 'kpse'
  kpse.set_program_name('luatex')
end)
---------------------------------------- logging
do
  local function log(...)
    local t = {program, ...}
    for i = 1, #t do t[i] = tostring(t[i]) end
    io.stderr:write(table.concat(t, ": ").."\n")
  end
  function info(...)
    if verbose >= 1 then log(...) end
  end
  function alert(...)
    if verbose >= 0 then log('WARNING', ...) end
  end
  function abort(...)
    log('ERROR', ...)
    os.exit(1)
  end
  function sure(val, ...)
    if val then return val, ... end
    abort(...)
  end
end
---------------------------------------- change name
do
  local function check_name(name1, name2)
    local p1, p2 = '^[\33-\126]+$', '[%(%)<>%{%}/%%]'
    local p3 = '^(%w+%-%w+)%-(.+)'
    local cs1, f1 = name1:match(p3)
    local cs2, f2 = name2:match(p3)
    sure(cs1 and name1:match(p1) and not name1:match(p2),
      "bad cmap name", name1)
    sure(cs2 and name2:match(p1) and not name2:match(p2),
      "bad cmap name", name2)
    sure(cs1 == cs2, ("glyph set differs (%s vs %s)"):format(cs1, cs2))
    return f1, f2
  end
  local function us_name(name)
    return (name:gsub('-', '_'))
  end
  function change_name(insrc, inname, outname)
    info("change cmap names", inname.." -> "..outname)
    local infn, outfn = check_name(inname, outname)
    info("       font names", infn.." -> "..outfn)
    local innu, outnu = us_name(inname), us_name(outname)
    local toks = sure(psyllium.parse(insrc))
    info("parsed", ("%d bytes, %d tokens"):format(#insrc, #toks))
    local pinfn = '%f[%w]'..infn:gsub('%W', '%%%0')..'%f[%W]'
    for i, tok in ipairs(toks) do
      if tok.t == 'name' or tok.t == 'lname' then
        if tok.v == inname then tok:set(outname) end
      elseif tok.t == 'string' then
        if tok.v == inname then tok:set(outname) end
        if tok.v == innu then tok:set(outnu) end
      elseif tok.t == 'comment' then
        local n = tok.src:gsub(pinfn, outfn)
        if n ~= tok.src then tok:set(n) end
      end
    end
    return sure(psyllium.form(toks))
  end
end
---------------------------------------- main procedure
do
  local function show_usage()
    io.stdout:write(([[
This is %s v%s <%s> by 'ZR'
Usage: %s[.lua] [<option>...] <in_file> <out_file>
  -v/--verbose    Show more messages
  -q/--quiet      Show fewer messages
  -h/--help       Show help and exit
  -V/--version    Show version and exit
]]):format(prog_name, version, mod_date, prog_name))
    os.exit(0)
  end
  function read_option()
    if #arg == 0 then show_usage() end
    local idx = 1
    while idx <= #arg do
      local opt = arg[idx]
      if opt:sub(1, 1) ~= "-" then break end
      if opt == "-h" or opt == "--help" then
        show_usage()
      elseif opt == "-v" or opt == "--verbose" then
        verbose = 1
      elseif opt == "-q" or opt == "--quiet" then
        verbose = 1
      else abort("invalid option", opt)
      end
      idx = idx + 1
    end
    sure(#arg == idx + 1, "wrong number of arguments")
    in_file, out_file = arg[idx], arg[idx + 1]
    if kpse then
      in_file = sure(kpse.find_file(in_file, 'cmap files', true),
        "CMap file not found on search path", arg[idx])
    end
  end
  local function cmap_name(pname)
    return pname:gsub('^.*[/\\]', '')
  end
  function main()
    read_option()
    info("input file path", in_file)
    info("output file path", out_file)
    local hin = sure(io.open(in_file, 'rb'),
      "cannot open file for read", in_file)
    local insrc = assert(hin:read('*a'))
    hin:close()
    info("change names in cmap data")
    local outsrc = change_name(insrc,
        cmap_name(in_file), cmap_name(out_file))
    info("write result")
    local hout = sure(io.open(out_file, 'wb'),
      "cannot open file for write", out_file)
    assert(hout:write(outsrc))
    hout:close()
    info("done")
  end
end
----------------------------------------
main()
-- EOF
