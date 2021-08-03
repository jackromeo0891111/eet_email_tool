#!/bin/bash

now=$(date +"%m_%d_%Y")
CUR_DIR=`dirname $0`
CUR_DIR=`cd $CUR_DIR; pwd`
LOCAL_MAIL_OUTPUT=/$CUR_DIR/email.txt
LOCAL_MAIL_OUTPUT_TMP=/$CUR_DIR/email.txt.tmp
LOCAL_MAIL_OUTPUT_ARCHIVE=/$CUR_DIR/email_head_archive/$now.email.txt
PARTIAL_TRIM=/$CUR_DIR/partial_trim.txt
PARTIAL_TRIM2=/$CUR_DIR/partial_trim2.txt
TEST_TRIM=/$CUR_DIR/test_trim.txt
TEST_TRIM2=/$CUR_DIR/test_trim2.txt
TEST_TRIM3=/$CUR_DIR/test_trim3.txt
CONFIG_TXT=$CUR_DIR/resources/config.txt
P4_FAIL=/$CUR_DIR/p4_fail.txt
P4_SUCCESS=/$CUR_DIR/p4_success.txt

TO_LOG=true
EMAIL_TO_ASSIGNEE=false
#EMAIL_TO_ASSIGNEE=true
echo 2016Password!| p4 login 1>$P4_SUCCESS 2>$P4_FAIL
# Set the default email list if no one is specified in environment variable
#DEFAULT_EMAIL="${DEFAULT_EMAIL:-jhung@ruckuswireless.com,raghu.dendukuri@ruckuswireless.com,kamran.bahadori@ruckuswireless.com}"
#DEFAULT_EMAIL="${DEFAULT_EMAIL:-jhung@ruckuswireless.com}"
DEFAULT_EMAIL="${DEFAULT_EMAIL:-jack.yeh@commscope.com}"
log() {
    if [ "$TO_LOG" = false ] ; then
        return
    fi
    >&2 echo $*
}

usage() {
    echo "Usage: TBD"
}

mock_local_email_output() {
    LOCAL_MAIL_OUTPUT=../unittest_files/email.txt
    LOCAL_MAIL_OUTPUT_TMP="$LOCAL_MAIL_OUTPUT.tmp"
}

email_header() {
    title=$1
    emails=$2
    echo "Prepare to send email notification: $title, $emails"
    now=`date +"%D"`
cat << EOF > $LOCAL_MAIL_OUTPUT
To: $emails
From: jack.yeh@commscope.com
Subject: [$title@$now] Fix Integration Reminder
MIME-Version: 1.0
Content-Type: text/html; charset="utf-8";


<html>
<body>
<h2>[$title@$now] Fix Integration Reminder</h2>
<h4>This is an automatic notification for missing fix integration for the past 6 weeks</h4>
Please refer to below entry for missing fixes.<br/><br/>
If fix is merged, please check: <br/>
    1. <b>Perforce Change List</b> has been filled out on JIRA.<br>
    2. Add <b>already-in-ML</b> or <b>not-applicable-to-ML</b> to labels of Jira after confirming CIC tool cannot recognize accordingly.

<br/><br/>
EOF
}

execute_by_config() {
    if [ -s $P4_FAIL ] ; then
    echo "--------P4 server and(or) jira is probably down now, will check again later--------" > $TEST_TRIM3
    config=$1
    cmd="`echo $config | cut -d '|' -f 3`"
    eval "$cmd > $LOCAL_MAIL_OUTPUT_TMP 2>&1"
    cat $TEST_TRIM3 | sed ':a;N;$!ba;s/\n/<br\/>/g' >> $LOCAL_MAIL_OUTPUT
    cp $LOCAL_MAIL_OUTPUT $LOCAL_MAIL_OUTPUT_ARCHIVE
    else
    config=$1
    cmd="`echo $config | cut -d '|' -f 3`"
    echo "Executing mr_tool.py to get output. It will take a while."
    log "Executing command: $cmd"
    eval "$cmd > $LOCAL_MAIL_OUTPUT_TMP 2>&1"
    cat $LOCAL_MAIL_OUTPUT_TMP | sed 's:ER/s:ERs:g' > $TEST_TRIM
    cat $TEST_TRIM | sed '1,/### Partial Integrated/d' > $PARTIAL_TRIM
    cat $PARTIAL_TRIM | sed '/### KSP or 3rd-party package/,$d' > $PARTIAL_TRIM2
    cat $TEST_TRIM | sed '1,/### Missing ERs by Assignees ###/d' > $TEST_TRIM2
    cat $TEST_TRIM2 | sed '/### Integrated ERs ###/,$d' > $TEST_TRIM3
    if [ -s $TEST_TRIM3 ] ; then
        echo "" >> $TEST_TRIM3
        echo "--------------Partially Integrated ER--------------" >> $TEST_TRIM3
        cat $PARTIAL_TRIM2 >> $TEST_TRIM3
    else
        echo "--------Good news!! No missing fix integration for the past six weeks!!--------" > $TEST_TRIM3
    fi 
    cat $TEST_TRIM3 | sed ':a;N;$!ba;s/\n/<br\/>/g' >> $LOCAL_MAIL_OUTPUT
    cp $LOCAL_MAIL_OUTPUT $LOCAL_MAIL_OUTPUT_ARCHIVE
    fi
}

email_footer() {
cat << EOF >> $LOCAL_MAIL_OUTPUT
</body>
</html>
EOF
    echo "OK"
}

get_email_list() {
    config=$1
    emails="`echo $config | cut -d '|' -f 1`,$DEFAULT_EMAIL"
    log $config
    log $emails
    log "EMAIL_TO_ASSIGNEE=$EMAIL_TO_ASSIGNEE"
    if [ "$EMAIL_TO_ASSIGNEE" = false ] ; then
        echo $emails
        return
    fi

    # Get email list
    EMAIL_START="### Missing ER/s by Assignees ###"
    EMAIL_END="### Integrated ER/s ###"

    start=false
    while read line
    do
        if [ "$line" = "$EMAIL_START" ] ; then
            start=true
            continue
        elif [ "$line" = "$EMAIL_END" ] ; then
            break
        fi
        
        if [ "$start" = false ] ; then
            continue
        fi

        email=`echo $line | sed -ne 's/^\[\(.*@.*\)\]$/\1/p'`

        if [ "$email" != "" ] ; then
            if [ "$emails" = "" ] ; then
                emails="$email"
            else
                emails="$emails,$email"
            fi
        fi
    done < $LOCAL_MAIL_OUTPUT_TMP

    log "assingeeEmails: $emails"
    
    echo "$DEFAULT_EMAIL,$emails"
}

send_email() {
    emailto=$1

    echo "Sending email..."
    echo "Emails: $emailto"
    /usr/sbin/ssmtp $emailto < $LOCAL_MAIL_OUTPUT
    if [ $? = 0 ] ; then
        echo "Sending email... Done"
    else
        echo "Sending email... Failed"
    fi
}

execute() {
    while read config
    do
        if [ ${config::1} = "#" ] ; then
            continue
        fi
        log $config
        title="`echo $config | cut -d '|' -f 2`"

        finalEmails=`get_email_list "$config"`

        log "Final emails: $finalEmails"

        email_header "$title" "$finalEmails"
        execute_by_config "$config"
        email_footer

        log "Before sending emails: $finalEmails"
        send_email "$finalEmails"

    done < $CONFIG_TXT
}

assert_equal() {
    res=$1
    expect=$2
    log "Assert Equal: $res" "$expect"
    if [[ "$res" =~ "$expect" ]] ; then
        echo "[OK]"
        exit 0
    fi
    echo "[Failed]"
    exit 1
}

opt=$1

case $opt in
    "test_get_email_list")
        mock_local_email_output
        while read config
        do
            if [ ${config::1} = "#" ] ; then
                continue
            fi
            EMAIL_TO_ASSIGNEE=true
            res=`get_email_list "$config"`
            assert_equal "$res" "jhung@ruckuswireless.com"
        done < $CONFIG_TXT
        ;;
    "test_send_email")
        mock_local_email_output
        res=`send_email $emails`
        assert_equal "$res" "Sending email... Done"
        ;;
    "test_email_footer")
        res=`email_footer`
        assert_equal "$res" "OK"
        ;;
    "execute")
        execute $*
        ;;
    *)
        echo `usage`
        exit 0
esac
rm $LOCAL_MAIL_OUTPUT
