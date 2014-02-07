# /etc/cron.d/koha-common
#
# Call koha-rebuild-zebra for each enabled Koha instance, to make sure the
# Zebra indexes are up to date.

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Comment the following line if you want to use the experimental koha-index-daemon integration
*/5 * * * * root test -x /usr/sbin/koha-rebuild-zebra && koha-rebuild-zebra -q $(koha-list --enabled)
*/15 * * * * root koha-foreach --enabled --email /usr/share/koha/bin/cronjobs/process_message_queue.pl
