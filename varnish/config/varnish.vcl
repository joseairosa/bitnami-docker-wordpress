# This is a basic VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.
#
# Default backend definition.  Set this to point to your content
# server.
#
vcl 4.0;

backend default {
  .host = "wordpress";
  .port = "80";
  .first_byte_timeout = 300s;
}

# import std;

include "lib/xforward.vcl";
include "lib/purge.vcl";
include "lib/bigfiles.vcl";
#include "lib/static.vcl";
include "lib/pagespeed.vcl";

sub vcl_recv {

  if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "DELETE") {
    return (pass);
  }
  # don't cache POSTs
  #if (req.method != "GET" &&
  #    req.method != "HEAD") {
  #  return(pass);
  #}

  if (req.http.Cookie ~ "wcaiocc_user_currency_cookie") {
    return (pass);
  }

  # don't cache for users logged into WP backend
  if (req.http.Cookie ~ "wp-postpass_|wordpress_logged_in_|comment_author") {
      return (pass);
  }

  # don't cache these special pages
  if (req.url ~ "nocache|wp-admin|wp-(comments-post|login|activate|mail)\.php|bb-admin|server-status|control\.php|bb-login\.php|bb-reset-password\.php|register\.php|ping\.php") {
    return(pass);
  }

  if (req.url ~ "preview=true" ||
      req.url ~ "xmlrpc.php" ||
      req.url ~ "^/API" ||
      req.url ~ "wc-api" ||
      req.url ~ "/feed/") {
    return (pass);
  }

  #if (req.http.X-Forwarded-For ~ "109.147.56.155") {
  #  return (pass);
  #}

  # don't cache unless it comes from https
  if (req.http.X-Forwarded-Proto !~ "(?i)https") {
    return (pass);
  }

  # don't cache ajax requests
  if (req.http.X-Requested-With == "XMLHttpRequest") {
    return (pass);
  }

  #unset req.http.cookie;
  # Unset Cookies except for WordPress admin and WooCommerce pages
  if (!(req.url ~ "(wp-login|wp-admin|cart|basket|my-account|my-lists|track-order|checkout|addons|logout|lost-password|product)")) {
    unset req.http.cookie;
  }
  # Pass through the WooCommerce dynamic pages
  if (req.url ~ "^/(cart|basket|my-account|my-lists|track-order|checkout|addons|logout|lost-password|product|sitemap)") {
    return (pass);
  }
  # Pass through the WooCommerce add to cart
  if (req.url ~ "\?add-to-cart=" ) {
    return (pass);
  }

  ### looks like we might actually cache it!
  # fix up the request
  set req.url = regsub(req.url, "\?replytocom=.*$", "");

  # Remove has_js, Google Analytics __*, and wooTracker cookies.
  set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|has_js|wooTracker)=[^;]*", "");
  set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");
  if (req.http.Cookie ~ "^\s*$") {
    unset req.http.Cookie;
  }

  return (hash);
}

#include "lib/hashed.vcl";

sub vcl_hash {
  # Add the browser cookie only if a WordPress cookie found.
  if (req.http.Cookie ~ "wp-postpass_|wordpress_logged_in_|comment_author|PHPSESSID") {
    hash_data(req.http.Cookie);
  }
}

sub vcl_backend_response {
  # make sure grace is at least 2 minutes
  if (beresp.grace < 2m) {
    set beresp.grace = 2m;
  }

  # catch obvious reasons we can't cache
  if (beresp.http.Set-Cookie) {
    set beresp.ttl = 0s;
  } else {
    set beresp.ttl = 60m;
  }

  # Varnish determined the object was not cacheable
  if (beresp.ttl <= 0s) {
    set beresp.http.X-Cacheable = "NO:Not Cacheable";
    set beresp.uncacheable = true;
    return (deliver);

  # You don't wish to cache content for logged in users
  } else if (bereq.http.Cookie ~ "wp-postpass_|wordpress_logged_in_|comment_author|wcaiocc_user_currency_cookie") {
    set beresp.http.X-Cacheable = "NO:Got Session";
    set beresp.uncacheable = true;
    return (deliver);

  # You are respecting the Cache-Control=private header from the backend
  } else if (beresp.http.Cache-Control ~ "private") {
    set beresp.http.X-Cacheable = "NO:Cache-Control=private";
    set beresp.uncacheable = true;
    return (deliver);

  # You are extending the lifetime of the object artificially
  } else if (beresp.ttl < 300s) {
    set beresp.ttl   = 300s;
    set beresp.grace = 300s;
    set beresp.http.X-Cacheable = "YES:Forced";

  # Varnish determined the object was cacheable
  } else {
    set beresp.http.X-Cacheable = "YES";
  }

  # Avoid caching error responses
  if (beresp.status == 404 || beresp.status >= 500) {
    set beresp.ttl   = 0s;
    set beresp.grace = 15s;
  }

  # Avoid caching redirects responses
  if (beresp.status == 301 || beresp.status == 302) {
    set beresp.ttl   = 0s;
    set beresp.grace = 15s;
  }

  # Unset Cookies except for WordPress admin and WooCommerce pages
  if ( (!(bereq.url ~ "(wp-(login|admin)|login|cart|my-account/*|my-lists/*|track-order/*|checkout|addons|logout|lost-password|product/*)")) || (bereq.method == "GET") ) {
    unset beresp.http.set-cookie;
  }
  #unset beresp.http.set-cookie;
  #set beresp.ttl = 60m;

  return (deliver);
}

sub vcl_deliver {
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
  } else {
    set resp.http.X-Cache = "MISS";
  }
  set resp.http.Access-Control-Allow-Origin = "*";
}

sub vcl_pipe {
  set bereq.http.connection = "close";
}
