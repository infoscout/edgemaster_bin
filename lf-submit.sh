#!/bin/bash
# Copyright 2010, 2011 Yu-Jie Lin
# BSD License

# Contains APIKEY and SECRET variables for last.fm credentials
source 'lf-submit.sh-secret'

APPNAME='lf-submit.sh'
USERAGENT="--user-agent '$APPNAME/0'"

API_BASE='http://ws.audioscrobbler.com/2.0/'
API_AUTH='http://www.last.fm/api/auth/'

_gen_signature_string () {
	while (($#>0)); do
		echo "${1/=/}"
		shift
	done | sort | tr -d '\n'
	}

gen_signature () {
	read signature _ <<< "$(echo -n "$(_gen_signature_string "$@")$SECRET" | md5sum)"
	}

_gen_http_param_string () {
	while (($#>0)); do
		# Percent-encoding the values
		echo "${1%%=*}=$(echo -n "${1#*=}" | perl -p -e 's/([^A-Za-z0-9-._~])/sprintf("%%%02X", ord($1))/seg')"
		shift
	done | sort | tr '\n' '&' | sed 's/&$//'
	}

gen_http_param_string () {
	http_param_string="$(_gen_http_param_string "$@")"
	}

extract_XML_value () {
	# $1 entity name
	# $2 string to find
	echo -n "$2" | egrep -o "<$1[^>]*>[^<]+" | sed -e "s/<$1[^>]*>//"
	}

get_lfm_status () {
	lfm_status="$(echo -n "$1" | sed '/lfm status/ {s/<lfm status="\(.*\)">/\1/;q 0} ; d')"
	}
	
setup_config () {
	read -p 'Please enter your Last.fm username: ' USERNAME
#	local PASSWORD_again
#	while :; do
#		read -s -p 'Please enter your Last.fm password: ' PASSWORD ; echo
#		read -s -p 'Please enter your Last.fm password again: ' PASSWORD_again ; echo
#		[[ "$PASSWORD" != "$PASSWORD_again" ]] && echo "Passwords do not match. Try again." || break
#	done
#	read PASSWORD _ <<< "$(echo -n "$PASSWORD" | md5sum)"

	# Fetch a request token
	echo "Getting a request token..."
	params=(
		"api_key=$APIKEY"
		"method=auth.getToken"
		)
	gen_signature "${params[@]}"
	params[${#params[@]}]="api_sig=$signature"
	gen_http_param_string "${params[@]}"
	
	resp=$(curl -s -G --data "$http_param_string" $USERAGENT "$API_BASE?$http_param_string")
	token="$(extract_XML_value 'token' "$resp")"

	echo "Please go to
	$API_AUTH?api_key=$APIKEY&token=$token
to authenticate $APPNAME.
"
	read -p "Press enter when you are done."

	# Fetch a web service session
	echo "Getting a session key..."
	params=(
		"api_key=$APIKEY"
		"method=auth.getSession"
		"token=$token"
		)
	gen_signature "${params[@]}"
	params[${#params[@]}]="api_sig=$signature"
	gen_http_param_string "${params[@]}"
	
	resp=$(curl -s -G --data "$http_param_string" $USERAGENT "$API_BASE?$http_param_string")
	SK="$(extract_XML_value 'key' "$resp")"

	# Writing to config file
	echo -n "Writing all data to $CONFIG_FILE..."
	echo "USERNAME=$USERNAME
SK=$SK" > "$CONFIG_FILE"
	echo "done"
	}

log () {
	[[ $LOG ]] && echo "[$(date -u +%FT%TZ)] $@" >> "$LOG_FILE"
	}

# Checking configuration

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="$XDG_CONFIG_HOME"/"$APPNAME"
CONFIG_FILE="$CONFIG_DIR"/config

[[ ! -d "$CONFIG_DIR" ]] && mkdir -p "$CONFIG_DIR"

if source "$CONFIG_FILE" &>/dev/null; then
	# Source successfully, checking required informations
	[[ -z "$USERNAME" || -z "$SK" ]] && setup_config

	[[ $LOG ]] && LOG_FILE=${LOG_FILE:-/tmp/$APPNAME.$(date -u +%FZ).log}
	log "$@"
	[[ $CURRENT_SONG_FILE ]] && CURRENT_SONG_FILE=/tmp/lf-submit.sh.currentsong

	case "$1" in
		-r|reset)
			setup_config
			;;
		-s|scrobble)
			shift
			params=(
				"$@"
				"api_key=$APIKEY"
				"method=track.scrobble"
				"sk=$SK"
				)

                        log "${params[@]}"
			gen_signature "${params[@]}"
			params[${#params[@]}]="api_sig=$signature"
			gen_http_param_string "${params[@]}"
			log "$http_param_string"
			resp=$(curl -s --data "$http_param_string" $USERAGENT "$API_BASE?$http_param_string")
			log "$resp"
			get_lfm_status "$resp"
			[[ "$lfm_status" != "ok" ]] && exit 1
			;;
		-n|now_playing)
			shift
			params=(
				"$@"
				"api_key=$APIKEY"
				"method=track.updateNowPlaying"
				"sk=$SK"
				)

                        log "${params[@]}"
			gen_signature "${params[@]}"
			params[${#params[@]}]="api_sig=$signature"
			gen_http_param_string "${params[@]}"
			log "$http_param_string"
			resp=$(curl -s --data "$http_param_string" $USERAGENT "$API_BASE?$http_param_string")
			log "$resp"
			get_lfm_status "$resp"
			[[ "$lfm_status" != "ok" ]] && exit 1
			;;
	esac
else
	setup_config
fi
