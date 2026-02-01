#!/usr/bin/env bash
#config.sh
#Data-only configuration for AIO Hardening Script
#Written by Colin Robertson
#Intended for use with main.sh

# ---- Splunk indexer / manager host (used for forwarder install) ----
# Internal IP for the Splunk machine (indexer/management).
SPLUNK_INDEXER_IP=""

# -----------------Role selection-----------------
#  Valid roles: ecomm | webmail | splunk
DEFAULT_ROLE=""

# ---------------Service-related Ports---------------
# Define common ports for each service profile

# Ecommerce (Ubuntu) - typical web stack
PORTS_ECOMM_TCP=(80 443)

# Webmail (Fedora) - common mail + webmail
# SMTP: 25, Submission: 587, SMTPS: 465 (if used)
# IMAP: 143, IMAPS: 993
# POP3: 110, POP3S: 995
# HTTP/HTTPS for webmail UI (if applicable): 80/443
PORTS_WEBMAIL_TCP=(25 465 587 110 995 143 993 80 443)

# Splunk (Oracle) - common ports:
# Web UI: 8000
# Management: 8089
# Forwarder receiving: 9997 (common)
# HEC: 8088 (optional; include if you use it)
PORTS_SPLUNK_TCP=(8000 8089 9997)

# --------- Host / dependency info ---------
