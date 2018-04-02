# purge.vcl -- Cache Purge Library for Varnish
#
# Copyright (C) 2013 DreamHost (New Dream Network, LLC)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# There are 3 possible behaviors of purging.

acl purge {
	"localhost";
	"127.0.0.1";
  "172.31.0.0"/20;
  "172.31.16.0"/20;
  "172.31.32.0"/20;
}

# Regex purging
# Treat the request URL as a regular expression.
sub purge_regex {
	ban("obj.http.X-Req-URL ~ " + req.url + " && obj.http.X-Req-Host == " + req.http.host);
}

# Exact purging
# Use the exact request URL (including any query params)
sub purge_exact {
	ban("obj.http.X-Req-URL == " + req.url + " && obj.http.X-Req-Host == " + req.http.host);
}

# Page purging (default)
# Use the exact request URL, but ignore any query params
sub purge_page {
	set req.url = regsub(req.url, "\?.*$", "");
	ban("obj.http.X-Req-URL-Base == " + req.url + " && obj.http.X-Req-Host == " + req.http.host);
}


# The purge behavior can be controlled with the X-Purge-Method header.
#
# Setting the X-Purge-Method header to contain "regex" or "exact" will use
# those respective behaviors.  Any other value for the X-Purge header will
# use the default ("page") behavior.
#
# The X-Purge-Method header is not case-sensitive.
#
# If no X-Purge-Method header is set, the request url is inspected to attempt
# a best guess as to what purge behavior is expected.  This should work for
# most cases, although if you want to guarantee some behavior you should
# always set the X-Purge-Method header.

sub vcl_recv {
  # Tell PageSpeed not to use optimizations specific to this request.
  set req.http.PS-CapabilityList = "fully general optimizations only";

  # Don't allow external entities to force beaconing.
  remove req.http.PS-ShouldBeacon;

	if (req.method == "PURGE") {

    if (client.ip !~ purge) {
			error 405 "Not allowed.";
		}

		if (req.http.X-Purge-Method) {
			if (req.http.X-Purge-Method ~ "(?i)regex") {
				call purge_regex;
			} elsif (req.http.X-Purge-Method ~ "(?i)exact") {
				call purge_exact;
			} else {
				call purge_page;
			}
		} else {
			# No X-Purge-Method header was specified.
			# Do our best to figure out which one they want.
			if (req.url ~ "\.\*" || req.url ~ "^\^" || req.url ~ "\$$" || req.url ~ "\\[.?*+^$|()]") {
				call purge_regex;
			} elsif (req.url ~ "\?") {
				call purge_exact;
			} else {
				call purge_page;
			}
		}

		return (lookup);
	}
}

sub vcl_backend_response {
	set beresp.http.X-Req-Host = req.http.host;
	set beresp.http.X-Req-URL = req.url;
	set beresp.http.X-Req-URL-Base = regsub(req.url, "\?.*$", "");

  # Mark HTML as uncacheable.  If we can't send them purge requests they can't
  # cache our html.
  if (beresp.http.Content-Type ~ "text/html") {
    remove beresp.http.Cache-Control;
    set beresp.http.Cache-Control = "no-cache, max-age=0";
  }
  return (deliver);
}

sub vcl_deliver {
	unset resp.http.X-Req-Host;
	unset resp.http.X-Req-URL;
	unset resp.http.X-Req-URL-Base;
}
