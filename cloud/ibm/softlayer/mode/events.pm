#
# Copyright 2018 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package cloud::ibm::softlayer::mode::events;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

my $instance_mode;

sub custom_status_threshold {
    my ($self, %options) = @_; 
    my $status = 'ok';
    my $message;
    
    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };
        
        if (defined($instance_mode->{option_results}->{critical_status}) && $instance_mode->{option_results}->{critical_status} ne '' &&
            eval "$instance_mode->{option_results}->{critical_status}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{warning_status}) && $instance_mode->{option_results}->{warning_status} ne '' &&
            eval "$instance_mode->{option_results}->{warning_status}") {
            $status = 'warning';
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_event_output {
    my ($self, %options) = @_;
    
    my $msg = sprintf("Status is '%s', Impacted items: %d", $self->{result_values}->{status}, $self->{result_values}->{items});
    return $msg;
}

sub custom_event_calc {
    my ($self, %options) = @_;
    
    $self->{result_values}->{id} = $options{new_datas}->{$self->{instance} . '_id'};
    $self->{result_values}->{subject} = $options{new_datas}->{$self->{instance} . '_subject'};
    $self->{result_values}->{status} = $options{new_datas}->{$self->{instance} . '_status'};
    $self->{result_values}->{items} = $options{new_datas}->{$self->{instance} . '_items'};
    return 0;
}

sub prefix_global_output {
    my ($self, %options) = @_;
    
    return "Number of events ";
}

sub prefix_events_output {
    my ($self, %options) = @_;
    
    return "Event '" . $options{instance_value}->{id} . "' with subject '" . $options{instance_value}->{subject} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => 0, cb_prefix_output => 'prefix_global_output', skipped_code => { -10 => 1 } },
        { name => 'events', type => 1, cb_prefix_output => 'prefix_events_output' },
    ];
    
    $self->{maps_counters}->{global} = [
        { label => 'active', set => {
                key_values => [ { name => 'active' } ],
                output_template => 'Active : %d',
                perfdatas => [
                    { label => 'active_events', value => 'active_absolute', template => '%d',
                      min => 0 },
                ],
            }
        },
        { label => 'completed', set => {
                key_values => [ { name => 'completed' } ],
                output_template => 'Completed : %d',
                perfdatas => [
                    { label => 'completed_events', value => 'completed_absolute', template => '%d',
                      min => 0 },
                ],
            }
        },
        { label => 'published', set => {
                key_values => [ { name => 'published' } ],
                output_template => 'Published : %d',
                perfdatas => [
                    { label => 'published_events', value => 'published_absolute', template => '%d',
                      min => 0 },
                ],
            }
        },
    ];
    $self->{maps_counters}->{events} = [
        { label => 'event', threshold => 0, set => {
                key_values => [ { name => 'id' }, { name => 'subject' }, { name => 'status' }, { name => 'items' } ],
                closure_custom_calc => $self->can('custom_event_calc'),
                closure_custom_output => $self->can('custom_event_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "filter-status:s"   => { name => 'filter_status', default => 'Active' },
                                  "warning-status:s"  => { name => 'warning_status', default => '' },
                                  "critical-status:s" => { name => 'critical_status', default => '%{status} =~ /Active/ && %{items} > 0' },
                                });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);
    
    $instance_mode = $self;
    $self->change_macros();
}

sub change_macros {
    my ($self, %options) = @_;
    
    foreach (('warning_status', 'critical_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

sub manage_selection {
    my ($self, %options) = @_;
    
    my %status_hash;
    my (undef, $events) = $options{custom}->get_endpoint(service => 'SoftLayer_Notification_Occurrence_Event', method => 'getAllObjects', extra_content => '');
    foreach my $event (@{$events->{'ns1:getAllObjectsResponse'}->{'getAllObjectsReturn'}->{'item'}}) {
        my $status;
        $status = $event->{statusCode}->{name}->{content} if (defined($event->{statusCode}->{name}->{content}));
        $status_hash{'#' . $event->{statusCode}->{id}} = $event->{statusCode}->{name}->{content} if (defined($event->{statusCode}->{name}->{content}));
        $status = $status_hash{$event->{statusCode}->{href}} if (!defined($event->{statusCode}->{name}->{content}) && defined($event->{statusCode}->{href}));

        next if (defined($self->{option_results}->{filter_status}) && $status !~ /$self->{option_results}->{filter_status}/);

        my $extra_content = '<slapi:SoftLayer_Notification_Occurrence_EventInitParameters>
  <id>' . $event->{id}->{content} . '</id>
</slapi:SoftLayer_Notification_Occurrence_EventInitParameters>';

        my (undef, $ressources) = $options{custom}->get_endpoint(service => 'SoftLayer_Notification_Occurrence_Event', method => 'getImpactedResources', extra_content => $extra_content);
        my $items = 0;
        if (defined($ressources->{'ns1:getImpactedResourcesResponse'}->{'getImpactedResourcesReturn'}->{'item'})) {
            $items = 1;
            $items = scalar(@{$ressources->{'ns1:getImpactedResourcesResponse'}->{'getImpactedResourcesReturn'}->{'item'}}) if (ref($ressources->{'ns1:getImpactedResourcesResponse'}->{'getImpactedResourcesReturn'}->{'item'}) eq 'ARRAY');
        }

        $self->{events}->{$event->{id}->{content}} = {
            id => $event->{id}->{content},
            subject => $event->{subject}->{content},
            status => $status,
            items => $items,
        };

        $self->{global}->{lc($status)}++;
    } 
}

1;

__END__

=head1 MODE

Check events status and number of impacted ressources

=over 8

=item B<--filter-status>

Filter events status (Default: 'Active')

=item B<--warning-status>

Set warning threshold for status (Default: '')
Can used special variables like: %{status}, %{items}.

=item B<--critical-status>

Set critical threshold for status (Default: '%{status} =~ /Active/ && %{items} > 0').
Can used special variables like: %{status}, %{items}.

=item B<--warning-*>

Threshold warning.
Can be: 'active', 'completed', 'published'.

=item B<--critical-*>

Threshold critical.
Can be: 'active', 'completed', 'published'.

=back

=cut
