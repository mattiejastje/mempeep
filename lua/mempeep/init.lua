return {
  descriptors = require("mempeep.descriptors"),
  errors = require("mempeep.errors"),
  read = require("mempeep.read"),
  tracers = {
    log_tracer = require("mempeep.tracers.log_tracer"),
    ok_tracer = require("mempeep.tracers.ok_tracer"),
  },
}
