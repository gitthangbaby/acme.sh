# renew certificates on DSM
acme=/root/.acme.sh/
$acme/acme.sh --cron --home $acme
err=$?
if [ ! $err == 0 ]; then #ACME gives 0 errorcode even when no action is taken, we catch other errors
   msg="Error running acme.sh ($err), see $acme/acme.sh.log"
   echo $msg
   synodsmnotify @administrators "Update certificate" "$msg"
   exit $err
fi

INFO=/usr/syno/etc/certificate/_archive/INFO
domains_processed=0 && domains_stalled=0
for domain_id in $(jq -r 'keys[]' $INFO); do
  domain=$(jq -r ".\"$domain_id\".desc" $INFO);
  num_services=$(jq -r ".\"$domain_id\".services|length" $INFO)
  src_path=/usr/syno/etc/certificate/_archive/$domain_id
  if [ -d "$src_path" -a -f "$acme/$domain/$domain.conf" ]; then #process only domains with ACME generated certificates
    echo Processing $domain \($domain_id\)...
    diff "$acme/$domain/fullchain.cer" "$src_path/cert.pem"
    if [ $? == 0 ]; then
        domains_stalled=`expr $domains_stalled + 1`
    else
        cp -a "$acme/$domain/fullchain.cer" "$src_path/cert.pem"
        cp -a "$acme/$domain/fullchain.cer" "$src_path/fullchain.pem"
        cp -a "$acme/$domain/cloud.pis.email.key" "$src_path/privkey.pem"
        cp -a "$acme/$domain/ca.cer" "$src_path/chain.pem"
    fi
    domains_processed=`expr $domains_processed + 1`
  else
    echo Skipping $domain \($domain_id\)...
  fi
done

if [ $domains_processed -le 0 ]; then #notify as we want at least one domain
    msg="Error copying source certificate folder to default one"
    echo $msg
    synodsmnotify @administrators "Update certificate" "$msg"
    exit 100
else
    echo $domains_processed domains processed with $domains_stalled having no changes
    if [ $domains_processed -gt $domains_stalled ]; then #notify and reload services only if at least one domain chnaged
      /usr/syno/sbin/synoservicectl --reload nginx
      $acme/reload-certs.sh
      if [ $? == 0 ]; then
        msg="Reloading certificates finished"
        echo $msg
        synodsmnotify @administrators "Update certificate" "$msg"
        exit 0
      else
        msg="Reloading certificates failed"
        echo $msg
        synodsmnotify @administrators "Update certificate" "$msg"
        exit 101
      fi
    fi
fi
