import os, strutils, nimando

var cmd_params: string
if paramCount() > 0:
  var params: seq[TaintedString]
  params = commandLineParams()
  cmd_params = strutils.join(params, " ")
  start(cmd_params)
else:
  start()
