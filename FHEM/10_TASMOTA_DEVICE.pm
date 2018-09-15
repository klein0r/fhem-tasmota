##############################################
#
# fhem bridge to mqtt (see http://mqtt.org)
#
# written 2017 by Matthias Kleine <info at haus-automatisierung.com>
#
##############################################

use strict;
use warnings;

my %gets = (
    "version" => "",
);

my %sets = (
    "cmd" => "",
    "on" => ":noArg",
    "off" => ":noArg",
    "toggle" => ":noArg",

    "Power" => ":on,off,toggle",
    "Upgrade" => ":1",
    "Status" => ":noArg",
    "OtaUrl" => "",

    "Clear" => ":noArg"
);

my @topics = qw(
    stat/POWER
    stat/UPGRADE
    stat/RESULT
    stat/STATUS
    stat/STATUS1
    stat/STATUS2
    stat/STATUS3
    stat/STATUS4
    stat/STATUS5
    stat/STATUS6
    stat/STATUS7
    stat/STATUS8
    stat/STATUS9
    stat/STATUS10
    stat/STATUS11
    tele/STATUS
    tele/LWT
    tele/ENERGY
    tele/INFO1
    tele/INFO2
    tele/INFO3
    tele/SENSOR
    tele/STATE
    tele/UPTIME
    tele/RESULT
);

sub TASMOTA_DEVICE_Initialize($) {
    my $hash = shift @_;

    # Consumer
    $hash->{DefFn} = "TASMOTA::DEVICE::Define";
    $hash->{UndefFn} = "TASMOTA::DEVICE::Undefine";
    $hash->{SetFn} = "TASMOTA::DEVICE::Set";
    $hash->{AttrFn} = "TASMOTA::DEVICE::Attr";
    $hash->{AttrList} = "IODev qos retain publishSet publishSet_.* subscribeReading_.* autoSubscribeReadings " . $main::readingFnAttributes;
    $hash->{OnMessageFn} = "TASMOTA::DEVICE::onmessage";

    main::LoadModule("MQTT");
    main::LoadModule("MQTT_DEVICE");
}

package TASMOTA::DEVICE;

use strict;
use warnings;
use POSIX;
use SetExtensions;
use GPUtils qw(:all);
use JSON;

use Net::MQTT::Constants;

BEGIN {
    MQTT->import(qw(:all));

    GP_Import(qw(
        CommandDeleteReading
        CommandAttr
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBeginUpdate
        readingsEndUpdate
        Log3
        SetExtensions
        SetExtensionsCancel
        fhem
        defs
        AttrVal
        ReadingsVal
    ))
};

sub Define() {
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);

    return "Invalid number of arguments: define <name> TASMOTA_DEVICE <topic> [<fullTopic>]" if (int(@args) < 1);

    my ($name, $type, $topic, $fullTopic) = @args;

    if (defined($topic)) {

        $hash->{TOPIC} = $topic;
        $hash->{MODULE_VERSION} = "0.5";
        $hash->{READY} = 0;

        if (defined($fullTopic) && $fullTopic ne "") {
            $fullTopic =~ s/%topic%/$topic/;
            $hash->{FULL_TOPIC} = $fullTopic;
        } else {
            # Default Sonoff/Tasmota topic
            $hash->{FULL_TOPIC} = "%prefix%/" . $topic . "/";
        }

        $hash->{TYPE} = 'MQTT_DEVICE';
        my $ret = MQTT::Client_Define($hash, $def);
        $hash->{TYPE} = $type;
        
        return $ret;
    }
    else {
        return "Topic missing";
    }
};

sub GetTopicFor($$) {
    my ($hash, $prefix) = @_;

    my $tempTopic = $hash->{FULL_TOPIC};
    $tempTopic =~ s/%prefix%/$prefix/;

    return $tempTopic;
}

sub Undefine($$) {
    my ($hash, $name) = @_;

    foreach (@topics) {
        my $oldTopic = TASMOTA::DEVICE::GetTopicFor($hash, $_);
        client_unsubscribe_topic($hash, $oldTopic);

        Log3($hash->{NAME}, 5, "automatically unsubscribed from topic: " . $oldTopic);
    }

    return MQTT::Client_Undefine($hash);
}

sub Set($$$@) {
    my ($hash, $name, $command, @values) = @_;

    if ($command eq '?' || $command =~ m/^(blink|intervals|(off-|on-)(for-timer|till)|toggle)/) {
        return SetExtensions($hash, join(" ", map { "$_$sets{$_}" } keys %sets) . " " . join(" ", map {$hash->{sets}->{$_} eq "" ? $_ : "$_:".$hash->{sets}->{$_}} sort keys %{$hash->{sets}}), $name, $command, @values);
    }

    Log3($hash->{NAME}, 5, "set " . $command . " - value: " . join (" ", @values));

    if (defined($sets{$command})) {
        my $msgid;
        my $retain = $hash->{".retain"}->{'*'};
        my $qos = $hash->{".qos"}->{'*'};

        if ($command eq "cmd") {
            my $cmnd = shift @values;
            my $topic = TASMOTA::DEVICE::GetTopicFor($hash, "cmnd/" . $cmnd);
            my $value = join (" ", @values);

            $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);

            Log3($hash->{NAME}, 5, "sent (cmnd) '" . $value . "' to " . $topic);
        } elsif ($command =~ m/^(on|off|toggle)$/s) {
            my $topic = TASMOTA::DEVICE::GetTopicFor($hash, "cmnd/Power");
            my $value = $1;

            $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);

            Log3($hash->{NAME}, 5, "sent (on, off, toggle) '" . $value . "' to " . $topic);
            
        } elsif ($command eq "Clear") {
            fhem("deletereading $name .*");

            Log3($hash->{NAME}, 5, "cleared all values");
        } else {
            my $topic = TASMOTA::DEVICE::GetTopicFor($hash, "cmnd/" . $command);
            my $value = join (" ", @values);

            $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);

            Log3($hash->{NAME}, 5, "sent '" . $value . "' to " . $topic);
        }

        $hash->{message_ids}->{$msgid}++ if defined $msgid;

        # Refresh Status

        my $statusTopic = TASMOTA::DEVICE::GetTopicFor($hash, "cmnd/Status");
        $msgid = send_publish($hash->{IODev}, topic => $statusTopic, message => "0", qos => $qos, retain => $retain);
        $hash->{message_ids}->{$msgid}++ if defined $msgid;

        Log3($hash->{NAME}, 5, "sent (cmnd) '0' to " . $statusTopic);

        SetExtensionsCancel($hash);
    } else {
        return MQTT::DEVICE::Set($hash, $name, $command, @values);
    }
}

sub Attr($$$$) {
    my ($command, $name, $attribute, $value) = @_;
    my $hash = $defs{$name};

    my $result = MQTT::DEVICE::Attr($command, $name, $attribute, $value);

    if ($attribute eq "IODev") {
        # Subscribe Readings
        foreach (@topics) {
            my $newTopic = TASMOTA::DEVICE::GetTopicFor($hash, $_);
            my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($newTopic);
            MQTT::client_subscribe_topic($hash, $mtopic, $mqos, $mretain);

            Log3($hash->{NAME}, 5, "automatically subscribed to topic: " . $newTopic);
        }

        $hash->{READY} = 1;
    }

    return $result;
}

sub onmessage($$$) {
    my ($hash, $topic, $message) = @_;

    Log3($hash->{NAME}, 5, "received message '" . $message . "' for topic: " . $topic);

    if ($topic =~ qr/.*\/?(stat|tele)\/([a-zA-Z1-9]+).*/ip) {
        my $type = lc($1);
        my $command = lc($2);
        my $isJSON = 1;

        if ($message !~ m/^\s*{.*}\s*$/s) {
            Log3($hash->{NAME}, 5, "no valid JSON, set reading as plain text: " . $message);
            $isJSON = 0;
        }

        Log3($hash->{NAME}, 5, "matched known type '" . $type . "' with command: " . $command);

        if ($type eq "stat" && $command eq "power") {
            Log3($hash->{NAME}, 4, "updating state to: '" . lc($message) . "'");

            readingsSingleUpdate($hash, "state", lc($message), 1);
        } elsif ($isJSON) {
            Log3($hash->{NAME}, 4, "json in message detected: '" . $message . "'");

            TASMOTA::DEVICE::Decode($hash, $command, $message);
        } else {
            Log3($hash->{NAME}, 4, "fallback to plain reading: '" . $message . "'");

            readingsSingleUpdate($hash, $command, $message, 1);
        }
    } else {
        # Forward to "normal" logic
        MQTT::DEVICE::onmessage($hash, $topic, $message);
    }
}

sub Expand($$$$) {
    my ($hash, $ref, $prefix, $suffix) = @_;

    $prefix = "" if (!$prefix);
    $suffix = "" if (!$suffix);
    $suffix = "-$suffix" if ($suffix);

    if (ref($ref) eq "ARRAY") {
        while (my ($key, $value) = each @{$ref}) {
            TASMOTA::DEVICE::Expand($hash, $value, $prefix . sprintf("%02i", $key + 1) . "-", "");
        }
    } elsif (ref($ref) eq "HASH") {
        while (my ($key, $value) = each %{$ref}) {
            if (ref($value)) {
                TASMOTA::DEVICE::Expand($hash, $value, $prefix . $key . $suffix . "-", "");
            } else {
                # replace illegal characters in reading names
                (my $reading = $prefix . $key . $suffix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;
                readingsBulkUpdate($hash, lc($reading), $value);
            }
        }
    }
}

sub Decode($$$) {
    my ($hash, $reading, $value) = @_;
    my $h;

    eval {
        $h = decode_json($value);
        1;
    };

    if ($@) {
        Log3($hash->{NAME}, 2, "bad JSON: $reading: $value - $@");
        return undef;
    }

    readingsBeginUpdate($hash);
    TASMOTA::DEVICE::Expand($hash, $h, $reading . "-", "");
    readingsEndUpdate($hash, 1);

    return undef;
}

1;

=pod
=item [device]
=item summary TASMOTA_DEVICE acts as a fhem-device that is mapped to mqtt-topics of the custom tasmota firmware
=begin html

<a name="TASMOTA_DEVICE"></a>
<h3>TASMOTA_DEVICE</h3>
<ul>
  <p>acts as a fhem-device that is mapped to <a href="http://mqtt.org/">mqtt</a>-topics.</p>
  <p>requires a <a href="#MQTT">MQTT</a>-device as IODev<br/>
     Note: this module is based on <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a> which needs to be installed from CPAN first.</p>
  <a name="TASMOTA_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; TASMOTA_DEVICE &lt;topic&gt; [&lt;fullTopic&gt;]</code><br/>
       Specifies the MQTT Tasmota device.</p>
  </ul>
  <a name="TASMOTA_DEVICEset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; &lt;command&gt;</code><br/>
         sets reading 'state' and publishes the command to topic configured via attr publishSet</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code><br/>
         sets reading &lt;reading&gt; and publishes the command to topic configured via attr publishSet_&lt;reading&gt;</p>
    </li>
  </ul>
  <a name="TASMOTA_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; publishSet [[&lt;reading&gt;:]&lt;commands_or_options&gt;] &lt;topic&gt;</code><br/>
         configures set commands and UI-options e.g. 'slider' that may be used to both set given reading ('state' if not defined) and publish to configured topic</p>
      <p>example:<br/>
      <code>attr mqttest publishSet on off switch:on,off level:slider,0,1,100 /topic/123</code>
      </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; publishSet_&lt;reading&gt; [&lt;values&gt;]* &lt;topic&gt;</code><br/>
         configures reading that may be used to both set 'reading' (to optionally configured values) and publish to configured topic</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; autoSubscribeReadings &lt;topic&gt;</code><br/>
         specify a mqtt-topic pattern with wildcard (e.c. 'myhouse/kitchen/+') and TASMOTA_DEVICE automagically creates readings based on the wildcard-match<br/>
         e.g a message received with topic 'myhouse/kitchen/temperature' would create and update a reading 'temperature'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; subscribeReading_&lt;reading&gt; [{Perl-expression}] [qos:?] [retain:?] &lt;topic&gt;</code><br/>
         mapps a reading to a specific topic. The reading is updated whenever a message to the configured topic arrives.<br/>
         QOS and ratain can be optionally defined for this topic. <br/>
         Furthermore, a Perl statement can be provided which is executed when the message is received. The following variables are available for the expression: $hash, $name, $topic, $message. Return value decides whether reading is set (true (e.g., 1) or undef) or discarded (false (e.g., 0)).
         </p>
      <p>Example:<br/>
         <code>attr mqttest subscribeReading_cmd {fhem("set something off")} /topic/cmd</code>
       </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; retain &lt;flags&gt; ...</code><br/>
         Specifies the retain flag for all or specific readings. Possible values are 0, 1</p>
      <p>Examples:<br/>
         <code>attr mqttest retain 0</code><br/>
         defines retain 0 for all readings/topics (due to downward compatibility)<br>
         <code> retain *:0 1 test:1</code><br/>
         defines retain 0 for all readings/topics except the reading 'test'. Retain for 'test' is 1<br>
       </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; qos &lt;flags&gt; ...</code><br/>
         Specifies the QOS flag for all or specific readings. Possible values are 0, 1 or 2. Constants may be also used: at-most-once = 0, at-least-once = 1, exactly-once = 2</p>
      <p>Examples:<br/>
         <code>attr mqttest qos 0</code><br/>
         defines QOS 0 for all readings/topics (due to downward compatibility)<br>
         <code> retain *:0 1 test:1</code><br/>
         defines QOS 0 for all readings/topics except the reading 'test'. Retain for 'test' is 1<br>
       </p>
    </li>
  </ul>
</ul>

=end html
=cut
