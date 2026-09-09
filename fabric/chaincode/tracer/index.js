"use strict";

const shim = require("fabric-shim");
const Tracer = require("./lib/tracer");

shim.start(new Tracer());