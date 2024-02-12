local package_name = "homie-millheat"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "homie-millheat"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Application that exposes Millheat devices to the Homie MQTT network",
  detailed = [[
    Application that exposes Millheat devices to the Homie MQTT network. It runs on
    top of the Copas scheduler and uses the Millheat HTTP API.
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.5",
  "luabitop",
  "homie",
  "lualogging >= 1.6.0, < 2",
  "millheat",
}

build = {
  type = "builtin",

  modules = {
    ["homie-millheat.init"] = "src/homie-millheat/init.lua",
  },

  install = {
    bin = {
      homiemillheat = "bin/homiemillheat.lua",
    }
  },

  copy_directories = {
    "docs",
  },
}
