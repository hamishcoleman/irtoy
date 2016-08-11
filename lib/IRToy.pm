package IRToy;
use warnings;
use strict;
#
# Support library for the IRtoy;
#

use Device::SerialPort;

use base 'Exporter';

use constant MODE_UNK    => 0;
use constant MODE_RC     => 1;
use constant MODE_SUMP   => 2;
use constant MODE_SAMPLE => 3;

our @EXPORT_OK = qw(MODE_UNK MODE_RC MODE_SUMP MODE_SAMPLE);
our %EXPORT_TAGS = (
    consts => ['MODE_UNK', 'MODE_RC', 'MODE_SUMP', 'MODE_SAMPLE']
);

# bleargh, boilerplate
#
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    #$self->_handle_args(@_);

    $self->{mode} = MODE_UNK;
    return $self;
}

sub debug {
    my $self = shift;
    my $debug = shift;
    if (defined($debug)) {
        $self->{debug} = $debug;
    }
    return $self->{debug};
}

sub open {
    my $self = shift;
    my $port = shift;
    my $sp = Device::SerialPort->new($port);

    if (!defined($sp)) {
        return undef;
    }

    # this is deliberately assuming a POSIX environment where stty can set
    # most of the serial port config before we open the port.
    # TODO
    # - confirm that the remaining settings are actually useful

    $sp->read_char_time(10);
    $sp->read_const_time(20);
    $sp->write_settings() || return undef;

    $self->{serialport} = $sp;
    return $self;
}

# write some bytes to the port
sub write {
    my $self = shift;
    my $buf = shift;

    if ($self->debug()) {
        print("DEBUG: write: ",unpack('H*',$buf),"\n");
    }

    return $self->{serialport}->write($buf);
}

# read some bytes from the port
sub read {
    my $self = shift;
    my $wanted = shift;

    my ($count,$buf) = $self->{serialport}->read($wanted);

    if ($self->debug()) {
        print("DEBUG: read() = ",$count,",",unpack('H*',$buf),"\n");
    }

    return ($count,$buf);
}

# Send the reset command to the toy
sub reset {
    my $self = shift;
    my $reset = chr(0)x5;
    my $count = $self->write($reset);
    if (!$count) {
        return undef;
    }
    if ($count != length($reset)) {
        warn("Short write");
    }

    # TODO
    # - is this short write ever encountered?
    # - should we wait for write_done() here?

    # unfortunately, the reset command has no response, so we just have to
    # assume it worked
    $self->{mode} = MODE_RC;

    # Slirp up any data in the buffer
    # TODO - this could just make it slower?
    $self->read(255);

    return $count;
}

# Send an IRman handshake
sub rc_id {
    my $self = shift;
    # TODO - should check current mode, but as this is an _id function, I
    # dont want to cause an infinite loop via the checkmode..
    $self->write('ir');
    my ($count,$buf) = $self->read(2);
    if ($buf eq 'OK') {
        # since we got the right response, we know what mode we are in
        $self->{mode} = MODE_RC;
        return $self;
    }
    return undef;
}

sub sump_id {
    my $self = shift;
    # TODO - same comment as in rc_id
    $self->write(chr(0x02));
    my ($count,$buf) = $self->read(4);
    if ($buf eq '1ALS') {
        # "SLA1" output LSB first
        return $self;
    }
    return undef;
}

# Check that we can talk to the irtoy, and are in the right mode
sub _mode_rc {
    my $self = shift;

    # Send a query command, success if we get good data
    return $self if (defined($self->rc_id()));

    # no good data, try a reset
    return undef if (!defined($self->reset()));

    # reset worked, try the query again
    return $self if (defined($self->rc_id()));

    return undef;
}

sub _mode_sump {
    my $self = shift;

    # to get to sump mode, we go to rc mode first..
    return undef if (!defined($self->checkmode(MODE_RC)));

    return $self->sump_id();
}

# comms and correct mode check
sub checkmode {
    my $self = shift;
    my $wantmode = shift;

    return undef if (!defined($wantmode));

    if ($self->{mode} == $wantmode) {
        return $self;
    }

    if ($wantmode == MODE_RC) {
        return $self->_mode_rc();
    }
    if ($wantmode == MODE_SUMP) {
        return $self->_mode_sump();
    }
    # TODO - add other modes here

    # no mode matched or worked
    return undef;
}

# IR sampling mode
sub mode_s {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_RC)));
    $self->write('s');
    my ($count,$buf) = $self->read(3); # slirp up expected response data
    if ($buf eq 'S01') {
        $self->{mode} = MODE_SAMPLE;
        return $self;
    }
    return undef;
}

sub selftest {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_RC)));
    $self->write('t');
    my ($count,$buf) = $self->read(4); # slirp up expected response data
    return $buf;

    # TODO
    # - return a true/false pass/fail
    # - stash the actual return value and have an accessor
    #
    # if $buf =~ /^V/ pass
    # if $buf =~ /^FA/ fail with errcode
    # else bad error
}

#
sub get_version {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_RC)));
    $self->write('v');
    my ($count,$buf) = $self->read(4); # slirp up expected response data
    if ($buf =~ /^V/) {
        return $buf;
    }
    return undef;
}

#
sub sump_meta {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_SUMP)));
    $self->write(chr(0x04));
    my ($count,$buf) = $self->read(5); # FIXME - should be variable sized
    return $buf;
    # TODO - this is a [tag,value]+,\x0 result buffer.. unpack it
}

# read an IRman packet
sub read_rc {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_RC)));

    my ($count, $buf) = $self->read(6);
    return $buf;
    # TODO
    # - find an RC5 remote and actually test this :-(
    # - return this as an object that can sanely use the data
}

sub sump_run {
    my $self = shift;
    return if (!defined($self->checkmode(MODE_SUMP)));
    $self->write(chr(0x01));

    # Note that there could be an indefinite delay until the first data arrives
    # as the irtoy waits for an IR signal.

    my $data = '';
    while (length($data) < 4096) {
        my ($count,$buf) = $self->read(128); # read size is a multiple of 4096
        $data .= $buf;
    }
    return $data;
    # TODO - return this as an object that can sanely use the data
}

# List of commands:
# RC decoder mode
# \x0 reset to RC decoder mode
# \x1 enter sump mode and - SUMP run
# \x2 enter sump mode and - SUMP ID - responds with "1ALS"
# "p" enter ir widget mode
# "r" irman handshake - responds with OK (done)
# "s" enter IR Sampling (done)
# "t" run selftest (done)
# "u" enter serial port bridge mode
# "v" show version - responds with "V1xx" (done)
# "$" enter bootloader

# SUMP mode
# \x0 reset to RC decoder mode
# \x1 SUMP run
# \x2 SUMP ID
# \x4 SUMP META - returns something like 4008310200

1;
