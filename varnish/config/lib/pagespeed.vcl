# pagespeed.vcl -- Pagespeed support

sub vcl_hit {
  # Make purging happen in response to a PURGE request.  This happens
  # automatically in Varnish 4.x so we don't need it there.
  if (req.method == "PURGE") {
    purge;
    error 200 "Purged.";
  }

  # 5% of the time ignore that we got a cache hit and send the request to the
  # backend anyway for instrumentation.
  if (std.random(0, 100) < 5) {
    set req.http.PS-ShouldBeacon = "animegamicache1337";
    return (pass);
  }
}

sub vcl_miss {
  # Make purging happen in response to a PURGE request.  This happens
  # automatically in Varnish 4.x so we don't need it there.
  if (req.method == "PURGE") {
    purge;
    error 200 "Purged.";
  }

  # Instrument 25% of cache misses.
  if (std.random(0, 100) < 25) {
    set req.http.PS-ShouldBeacon = "animegamicache1337";
    return (pass);
  }
}
