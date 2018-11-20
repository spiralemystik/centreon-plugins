package hardware::server::huawei::ibmc::snmp::mode::components::component;

use strict;
use warnings;

my $mapping = {
    firmwareName                => { oid => ' .1.3.6.1.4.1.2011.2.235.1.1.11.50.1.1' },
    firmwareVersion             => { oid => ' .1.3.6.1.4.1.2011.2.235.1.1.11.50.1.4', },
};
my $oid_ firmwareDescriptionEntry = ' .1.3.6.1.4.1.2011.2.235.1.1.11.50.1';

sub load {
    my ($self) = @_;
    
    push @{$self->{request}}, { oid => $oid_ firmwareDescriptionEntry };
}

sub check {
    my ($self) = @_;

    $self->{output}->output_add(long_msg => "Checking firmware");
    $self->{components}->{component} = {name => 'firmware', total => 0, skip => 0};
    return if ($self->check_filter(section => 'firmware'));

    foreach my $oid ($self->{snmp}->oid_lex_sort(keys %{$self->{results}->{$oid_firmwareDescriptionEntry}})) {
        my $instance = $1;
        my $result = $self->{snmp}->map_instance(mapping => $mapping, results => $self->{results}->{$oid_firmwareDescriptionEntry}, instance => $instance);

        next if ($self->check_filter(section => 'firmware', instance => $instance));
        $self->{firmware}->{firmware}->{total}++;
        
        $self->{output}->output_add(long_msg => sprintf("'%s' firmware version is '%s' [instance = %s]",
                                    $result->{firmwareName}, $result->{firmwareVersion}, $instance, 
                                    ));
        }
    }
}

1;
