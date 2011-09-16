package iControl;

use strict;
no warnings 'redefine';

use Carp qw(confess croak);
use Exporter;
use SOAP::Lite;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

@ISA			= qw(Exporter);
$VERSION 		= '0.03';

=head1 NAME

iControl - A Perl interface to the F5 iControl API

=head1 SYNOPSIS

        use iControl;

        my $ic = iControl->new(
                                server		=> 'bigip.company.com',
                                username	=> 'api_user',
                                password	=> 'my_password',
                                port		=> 443,
                                proto		=> 'https'
                        );

	my $virtual	= ($ic->get_vs_list())[0];

	my %stats	= $ic->get_vs_statistics_stringified($virtual);;

	print '*'x50,"\nVirtual: $virtual\n",'*'x50,"\nTimestamp: $stats{timestamp}\n";

	foreach my $s (sort keys %{$stats{stats}}) {
		print "$s\t$stats{stats}{$s}\n"
	}

=head1 DESCRIPTION

This package provides a Perl interface to the F5 iControl API.

The F5 iControl API is an open SOAP/XML for communicating with supported F5 BIGIP products.

The primary aim of this package is to provide a simplified interface to an already simple and
intutive API and to allow the user to do more with less code.  By reducing the API invocations
to methods returning simple types, it is hoped that this module will provide a simple alternative
for common tasks.

The secondary aim for this package is to provide a simple interface for accessing statistical
data from the iControl API for monitoring, recording, archival and display in other systems.
This objective has largely been obsoleted in v11 with the introduction of new statistical
monitoring and display features in the web UI.

This package generally provides two methods for each each task; a raw method typically returning
the response as received from iControl, and a "stringified" method returning a parsed response.

In general, the stringified methods will typically fufill most requirements and should usually
be easier to use.

=cut

our $urn_map;

# Our implementation of the iControl API
# Refer to http://devcentral.f5.com/wiki/iControl.APIReference.ashx for complete detail.

our $modules	= { 
		ARX		=>	{},
		ASM		=>	{},
		Common		=>	{},
		GlobalLB	=>	{},
		LTConfig	=>	{},
		LocalLB		=>	{
					VirtualServer	=>	{
								get_list		=> 0,
								get_default_pool_name	=> 'virtual_servers',
								get_destination		=> 'virtual_servers',
								get_enabled_state	=> 'virtual_servers',
								get_statistics		=> 'virtual_servers',
								get_all_statistics	=> 0
								},
					Pool		=>	{
								get_list		=> 0,
								get_member		=> 'pool_names',
								get_statistics		=> 'pool_names',
								get_all_statistics	=> 'pool_names'
								},
					PoolMember	=>	{
								get_statistics		=> {pool_names => 1, members => 1},
								get_all_statistics	=> 'pool_names'
								},
					NodeAddress	=>	{
								get_list		=> 0,
								get_screen_name		=> 'node_addresses',
								get_object_status	=> 'node_addresses',
								get_monitor_status	=> 'node_addresses',
								get_statistics		=> 'node_addresses'
								}
					},
		Management	=> 	{
					EventSubscription=>	{
								create			=> 'sub_detail_list',
								get_list		=> 0
								}
					},
		Networking	=> 	{
					Interfaces	=>	{
								get_list		=> 0,
								get_statistics		=> 'interfaces'
								}
					},
		System		=> 	{
					ConfigSync	=>	{
								save_configuration	=> 0,
								download_configuration	=> 0
								},
					SystemInfo	=>	{
								get_system_information	=> 0
								},
					Cluster		=>	{
								get_cluster_enabled_state=> 'cluster_names',
								get_list		=> 0
								},
					Failover	=>	{
								get_failover_mode	=> 0,
								get_failover_state	=> 0,
								is_redundant		=> 0
								}
					},
		WebAccelerator	=> 	{}
		};

our $event_types= {
		EVENTTYPE_NONE			=>	1,
		EVENTTYPE_TEST			=>	1,
		EVENTTYPE_ALL			=>	1,
		EVENTTYPE_SYSTEM_STARTUP	=>	1,
		EVENTTYPE_SYSTEM_SHUTDOWN	=>	1,
		EVENTTYPE_SYSTEM_CONFIG_LOAD	=>	1,
		EVENTTYPE_CREATE		=>	1,
		EVENTTYPE_MODIFY		=>	1,
		EVENTTYPE_DELETE		=>	1,
		EVENTTYPE_ADMIN_IP		=>	1,
		EVENTTYPE_ARP_ENTRY		=>	1,
		EVENTTYPE_DAEMON_HA		=>	1,
		EVENTTYPE_DB_VARIABLE		=>	1,
		EVENTTYPE_FEATURE_FLAGS		=>	1,
		EVENTTYPE_FILTER_PROFILE	=>	1,
		EVENTTYPE_GTMD			=>	1,
		EVENTTYPE_INTERFACE		=>	1,
		EVENTTYPE_LCDWARN		=>	1,
		EVENTTYPE_L2_FORWARD		=>	1,
		EVENTTYPE_MIRROR_PORT_MEMBER	=>	1,
		EVENTTYPE_MIRROR_PORT		=>	1,
		EVENTTYPE_MIRROR_VLAN		=>	1,
		EVENTTYPE_MONITOR		=>	1,
		EVENTTYPE_NAT			=>	1,
		EVENTTYPE_NODE_ADDRESS		=>	1,
		EVENTTYPE_PACKET_FILTER		=>	1,
		EVENTTYPE_PCI_DEVICE		=>	1,
		EVENTTYPE_POOL			=>	1,
		EVENTTYPE_POOL_MEMBER		=>	1,
		EVENTTYPE_RATE_FILTER		=>	1,
		EVENTTYPE_ROUTE_MGMT		=>	1,
		EVENTTYPE_ROUTE_UPDATE		=>	1,
		EVENTTYPE_RULE			=>	1,
		EVENTTYPE_SELF_IP		=>	1,
		EVENTTYPE_SENSOR		=>	1,
		EVENTTYPE_SNAT_ADDRESS		=>	1,
		EVENTTYPE_SNAT_POOL		=>	1,
		EVENTTYPE_SNAT_POOL_MEMBER	=>	1,
		EVENTTYPE_STP			=>	1,
		EVENTTYPE_SWITCH_DOMAIN		=>	1,
		EVENTTYPE_SWITCH_EDGE		=>	1,
		EVENTTYPE_TAMD_AUTH		=>	1,
		EVENTTYPE_TRUNK			=>	1,
		EVENTTYPE_TRUNK_CONFIG_MEMBER	=>	1,
		EVENTTYPE_TRUNK_WORKING_MEMBER	=>	1,
		EVENTTYPE_VALUE_LIST		=>	1,
		EVENTTYPE_VIRTUAL_ADDRESS	=>	1,
		EVENTTYPE_VIRTUAL_SERVER	=>	1,
		EVENTTYPE_VIRTUAL_SERVER_PROFILE=>	1,
		EVENTTYPE_VLAN			=>	1,
		EVENTTYPE_VLAN_MEMBER		=>	1,
		EVENTTYPE_VLANGROUP		=>	1
		};


sub BEGIN {

	$urn_map= {
		"{urn:iControl}ASM.ApplyLearningType"					=> 1,
		"{urn:iControl}ASM.DynamicSessionsInUrlType" 				=> 1,
		"{urn:iControl}ASM.FlagState" 						=> 1,
		"{urn:iControl}ASM.PolicyTemplate" 					=> 1,
		"{urn:iControl}ASM.ProtocolType" 					=> 1,
		"{urn:iControl}ASM.SeverityName" 					=> 1,
		"{urn:iControl}ASM.ViolationName" 					=> 1,
		"{urn:iControl}ASM.WebApplicationLanguage" 				=> 1,
		"{urn:iControl}Common.ArmedState" 					=> 1,
		"{urn:iControl}Common.AuthenticationMethod" 				=> 1,
		"{urn:iControl}Common.AvailabilityStatus" 				=> 1,
		"{urn:iControl}Common.DaemonStatus" 					=> 1,
		"{urn:iControl}Common.EnabledState" 					=> 1,
		"{urn:iControl}Common.EnabledStatus" 					=> 1,
		"{urn:iControl}Common.FileChainType" 					=> 1,
		"{urn:iControl}Common.HAAction" 					=> 1,
		"{urn:iControl}Common.HAState" 						=> 1,
		"{urn:iControl}Common.IPHostType" 					=> 1,
		"{urn:iControl}Common.ProtocolType" 					=> 1,
		"{urn:iControl}Common.SourcePortBehavior" 				=> 1,
		"{urn:iControl}Common.StatisticType" 					=> 1,
		"{urn:iControl}Common.TMOSModule" 					=> 1,
		"{urn:iControl}GlobalLB.AddressType" 					=> 1,
		"{urn:iControl}GlobalLB.AutoConfigurationState" 			=> 1,
		"{urn:iControl}GlobalLB.AvailabilityDependency" 			=> 1,
		"{urn:iControl}GlobalLB.LBMethod" 					=> 1,
		"{urn:iControl}GlobalLB.LDNSProbeProtocol" 				=> 1,
		"{urn:iControl}GlobalLB.LinkWeightType" 				=> 1,
		"{urn:iControl}GlobalLB.MetricLimitType" 				=> 1,
		"{urn:iControl}GlobalLB.MonitorAssociationRemovalRule" 			=> 1,
		"{urn:iControl}GlobalLB.MonitorInstanceStateType" 			=> 1,
		"{urn:iControl}GlobalLB.MonitorRuleType" 				=> 1,
		"{urn:iControl}GlobalLB.RegionDBType" 					=> 1,
		"{urn:iControl}GlobalLB.RegionType" 					=> 1,
		"{urn:iControl}GlobalLB.ServerType" 					=> 1,
		"{urn:iControl}GlobalLB.Application.ApplicationObjectType" 		=> 1,
		"{urn:iControl}GlobalLB.DNSSECKey.KeyAlgorithm" 			=> 1,
		"{urn:iControl}GlobalLB.DNSSECKey.KeyType" 				=> 1,
		"{urn:iControl}GlobalLB.Monitor.IntPropertyType" 			=> 1,
		"{urn:iControl}GlobalLB.Monitor.StrPropertyType" 			=> 1,
		"{urn:iControl}GlobalLB.Monitor.TemplateType" 				=> 1,
		"{urn:iControl}LocalLB.AddressType" 					=> 1,
		"{urn:iControl}LocalLB.AuthenticationMethod" 				=> 1,
		"{urn:iControl}LocalLB.AvailabilityStatus" 				=> 1,
		"{urn:iControl}LocalLB.ClientSSLCertificateMode" 			=> 1,
		"{urn:iControl}LocalLB.ClonePoolType" 					=> 1,
		"{urn:iControl}LocalLB.CompressionMethod" 				=> 1,
		"{urn:iControl}LocalLB.CookiePersistenceMethod" 			=> 1,
		"{urn:iControl}LocalLB.CredentialSource" 				=> 1,
		"{urn:iControl}LocalLB.EnabledStatus" 					=> 1,
		"{urn:iControl}LocalLB.HardwareAccelerationMode" 			=> 1,
		"{urn:iControl}LocalLB.HttpChunkMode" 					=> 1,
		"{urn:iControl}LocalLB.HttpCompressionMode" 				=> 1,
		"{urn:iControl}LocalLB.HttpRedirectRewriteMode" 			=> 1,
		"{urn:iControl}LocalLB.LBMethod" 					=> 1,
		"{urn:iControl}LocalLB.MonitorAssociationRemovalRule" 			=> 1,
		"{urn:iControl}LocalLB.MonitorInstanceStateType" 			=> 1,
		"{urn:iControl}LocalLB.MonitorRuleType" 				=> 1,
		"{urn:iControl}LocalLB.MonitorStatus"					=> 1,
		"{urn:iControl}LocalLB.PersistenceMode" 				=> 1,
		"{urn:iControl}LocalLB.ProfileContextType" 				=> 1,
		"{urn:iControl}LocalLB.ProfileMode" 					=> 1,
		"{urn:iControl}LocalLB.ProfileType" 					=> 1,
		"{urn:iControl}LocalLB.RamCacheCacheControlMode" 			=> 1,
		"{urn:iControl}LocalLB.RtspProxyType" 					=> 1,
		"{urn:iControl}LocalLB.SSLOption" 					=> 1,
		"{urn:iControl}LocalLB.ServerSSLCertificateMode" 			=> 1,
		"{urn:iControl}LocalLB.ServiceDownAction" 				=> 1,
		"{urn:iControl}LocalLB.SessionStatus" 					=> 1,
		"{urn:iControl}LocalLB.SnatType" 					=> 1,
		"{urn:iControl}LocalLB.TCPCongestionControlMode" 			=> 1,
		"{urn:iControl}LocalLB.TCPOptionMode" 					=> 1,
		"{urn:iControl}LocalLB.UncleanShutdownMode" 				=> 1,
		"{urn:iControl}LocalLB.VirtualAddressStatusDependency" 			=> 1,
		"{urn:iControl}LocalLB.Class.ClassType" 				=> 1,
		"{urn:iControl}LocalLB.Class.FileFormatType" 				=> 1,
		"{urn:iControl}LocalLB.Class.FileModeType" 				=> 1,
		"{urn:iControl}LocalLB.Monitor.IntPropertyType" 			=> 1,
		"{urn:iControl}LocalLB.Monitor.StrPropertyType" 			=> 1,
		"{urn:iControl}LocalLB.Monitor.TemplateType" 				=> 1,
		"{urn:iControl}LocalLB.ProfilePersistence.PersistenceHashMethod"	=> 1,
		"{urn:iControl}LocalLB.ProfileUserStatistic.UserStatisticKey" 		=> 1,
		"{urn:iControl}LocalLB.RAMCacheInformation.RAMCacheVaryType"		=> 1,
		"{urn:iControl}LocalLB.RateClass.DirectionType" 			=> 1,
		"{urn:iControl}LocalLB.RateClass.DropPolicyType" 			=> 1,
		"{urn:iControl}LocalLB.RateClass.QueueType" 				=> 1,
		"{urn:iControl}LocalLB.RateClass.UnitType" 				=> 1,
		"{urn:iControl}LocalLB.VirtualServer.VirtualServerCMPEnableMode"	=> 1,
		"{urn:iControl}LocalLB.VirtualServer.VirtualServerType" 		=> 1,
		"{urn:iControl}Management.DebugLevel" 					=> 1,
		"{urn:iControl}Management.LDAPPasswordEncodingOption" 			=> 1,
		"{urn:iControl}Management.LDAPSSLOption" 				=> 1,
		"{urn:iControl}Management.LDAPSearchMethod" 				=> 1,
		"{urn:iControl}Management.LDAPSearchScope" 				=> 1,
		"{urn:iControl}Management.OCSPDigestMethod" 				=> 1,
		"{urn:iControl}Management.ZoneType" 					=> 1,
		"{urn:iControl}Management.EventNotification.EventDataType" 		=> 1,
		"{urn:iControl}Management.EventSubscription.AuthenticationMode" 	=> 1,
		"{urn:iControl}Management.EventSubscription.EventType" 			=> 1,
		"{urn:iControl}Management.EventSubscription.ObjectType" 		=> 1,
		"{urn:iControl}Management.EventSubscription.SubscriptionStatusCode" 	=> 1,
		"{urn:iControl}Management.KeyCertificate.CertificateType" 		=> 1,
		"{urn:iControl}Management.KeyCertificate.KeyType" 			=> 1,
		"{urn:iControl}Management.KeyCertificate.ManagementModeType" 		=> 1,
		"{urn:iControl}Management.KeyCertificate.SecurityType" 			=> 1,
		"{urn:iControl}Management.KeyCertificate.ValidityType" 			=> 1,
		"{urn:iControl}Management.Provision.ProvisionLevel" 			=> 1,
		"{urn:iControl}Management.SNMPConfiguration.AuthType" 			=> 1,
		"{urn:iControl}Management.SNMPConfiguration.DiskCheckType" 		=> 1,
		"{urn:iControl}Management.SNMPConfiguration.LevelType" 			=> 1,
		"{urn:iControl}Management.SNMPConfiguration.ModelType" 			=> 1,
		"{urn:iControl}Management.SNMPConfiguration.PrefixType" 		=> 1,
		"{urn:iControl}Management.SNMPConfiguration.PrivacyProtocolType"	=> 1,
		"{urn:iControl}Management.SNMPConfiguration.SinkType" 			=> 1,
		"{urn:iControl}Management.SNMPConfiguration.TransportType" 		=> 1,
		"{urn:iControl}Management.SNMPConfiguration.ViewType" 			=> 1,
		"{urn:iControl}Management.UserManagement.UserRole" 			=> 1,
		"{urn:iControl}Networking.FilterAction" 				=> 1,
		"{urn:iControl}Networking.FlowControlType" 				=> 1,
		"{urn:iControl}Networking.LearningMode" 				=> 1,
		"{urn:iControl}Networking.MediaStatus" 					=> 1,
		"{urn:iControl}Networking.MemberTagType" 				=> 1,
		"{urn:iControl}Networking.MemberType" 					=> 1,
		"{urn:iControl}Networking.PhyMasterSlaveMode" 				=> 1,
		"{urn:iControl}Networking.RouteEntryType" 				=> 1,
		"{urn:iControl}Networking.STPLinkType" 					=> 1,
		"{urn:iControl}Networking.STPModeType" 					=> 1,
		"{urn:iControl}Networking.STPRoleType" 					=> 1,
		"{urn:iControl}Networking.STPStateType" 				=> 1,
		"{urn:iControl}Networking.ARP.NDPState" 				=> 1,
		"{urn:iControl}Networking.Interfaces.MediaType" 			=> 1,
		"{urn:iControl}Networking.ProfileWCCPGRE.WCCPGREForwarding" 		=> 1,
		"{urn:iControl}Networking.STPInstance.PathCostType" 			=> 1,
		"{urn:iControl}Networking.SelfIPPortLockdown.AllowMode" 		=> 1,
		"{urn:iControl}Networking.Trunk.DistributionHashOption" 		=> 1,
		"{urn:iControl}Networking.Trunk.LACPTimeoutOption" 			=> 1,
		"{urn:iControl}Networking.Trunk.LinkSelectionPolicy" 			=> 1,
		"{urn:iControl}Networking.Tunnel.TunnelDirection" 			=> 1,
		"{urn:iControl}Networking.VLANGroup.VLANGroupTransparency" 		=> 1,
		"{urn:iControl}Networking.iSessionLocalInterface.NatSourceAddress" 	=> 1,
		"{urn:iControl}Networking.iSessionPeerDiscovery.DiscoveryMode" 		=> 1,
		"{urn:iControl}Networking.iSessionPeerDiscovery.FilterMode" 		=> 1,
		"{urn:iControl}Networking.iSessionRemoteInterface.NatSourceAddress" 	=> 1,
		"{urn:iControl}Networking.iSessionRemoteInterface.OriginState" 		=> 1,
		"{urn:iControl}System.CPUMetricType" 					=> 1,
		"{urn:iControl}System.FanMetricType" 					=> 1,
		"{urn:iControl}System.HardwareType" 					=> 1,
		"{urn:iControl}System.PSMetricType" 					=> 1,
		"{urn:iControl}System.TemperatureMetricType" 				=> 1,
		"{urn:iControl}System.ConfigSync.ConfigExcludeComponent" 		=> 1,
		"{urn:iControl}System.ConfigSync.ConfigIncludeComponent" 		=> 1,
		"{urn:iControl}System.ConfigSync.LoadMode" 				=> 1,
		"{urn:iControl}System.ConfigSync.SaveMode" 				=> 1,
		"{urn:iControl}System.ConfigSync.SyncMode" 				=> 1,
		"{urn:iControl}System.Disk.RAIDStatus" 					=> 1,
		"{urn:iControl}System.Failover.FailoverMode" 				=> 1,
		"{urn:iControl}System.Failover.FailoverState" 				=> 1,
		"{urn:iControl}System.Services.ServiceAction" 				=> 1,
		"{urn:iControl}System.Services.ServiceStatusType" 			=> 1,
		"{urn:iControl}System.Services.ServiceType" 				=> 1,
		"{urn:iControl}System.Statistics.GtmIQueryState" 			=> 1,
		"{urn:iControl}System.Statistics.GtmPathStatisticObjectType" 		=> 1,
	};

	package iControlDeserializer;
	@iControlDeserializer::ISA = 'SOAP::Deserializer';

	sub typecast {
		my ($self, $value, $name, $attrs, $children, $type) = @_;
		my $retval = undef;
		if (! defined $type or ! defined $urn_map->{$type}) {return $retval}
		if ($urn_map->{$type} == 1) {$retval = $value}
		return $retval;
	}
}

=head2 METHODS

=head3 new (%args)

	my $ic = iControl->new(
				server		=> 'bigip.company.com',
				username	=> 'api_user',
				password	=> 'my_password',
				port		=> 443,
				proto		=> 'https'
			);

Constructor method.  Creates a new iControl object representing a single interface into the iControl API
of the target system.

Required parameters are:

=over 3

=item server

The target F5 BIGIP device.  The supplied value may be either an IP address, FQDN or resolvable hostname.

=item username

The username with which to connect to the iControl API.

=item password

The password with which to connect to the iControl API.

=item port

The port on which to connect to the iControl API.

=item proto

The protocol with to use for communications with the iControl API (should be either http or https).

=back

=cut

sub new {
	@_ == 11		or croak 'Not enough arguments for constructor';
	my ($class, %args) 	= @_;
	my $self 		= bless({}, $class);
	defined $args{server}	? $self->{server} 	= $args{server}		: croak 'Constructor failed: server not defined';
	defined $args{username}	? $self->{username} 	= $args{username}	: croak 'Constructor failed: username not defined';
	defined $args{password}	? $self->{password} 	= $args{password}	: croak 'Constructor failed: password not defined';
	defined $args{port}	? $self->{port} 	= $args{port}		: croak 'Constructor failed: port not defined';
	defined $args{proto}	? $self->{proto} 	= $args{proto}		: croak 'Constructor failed: proto not defined';
	sub SOAP::Transport::HTTP::Client::get_basic_credentials {return $self->{username} => $self->{password}}
	$self->{_client}	= SOAP::Lite->proxy($self->{proto}.'://'.$self->{server}.':'.$self->{port}.'/iControl/iControlPortal.cgi')->deserializer(iControlDeserializer->new());
	return $self;
}

sub _set_uri {
	my ($self, $module, $interface)	= @_;
	$self->{_client}->uri("urn:iControl:$module/$interface")
}

sub _unset_uri {
	my $self	= shift;
	undef $self->{_client}->{uri};
}

sub _get_username {
	my $self	= shift;
	return $self->{username};
}

# We do most of our request validation in this method so it is unnessecarily complex, not entirely intuitive, uglier
# than a hat full of assholes and slightly less elegant than Lindsay Lohan exiting a limo.
#
# By pushing complexity from our public methods into here, we can implement some basic checks against known bad
# invocations rather than just passing them through to iControl to handle.
# 
# It also allows us to limit the over-riding or abuse of the internal _request method by limiting
# invocations to the parameter format specified in global $modules struct.
#
# We can then implement accessor methods by essentially copying the API invocation from the reference.  For example,
# to implement the System::SystemInfo::get_system_id API call, the reference gives the prototype as;
#
#  String get_system_id();
#
# Note also that the API uses the namespace convention of Module::Interface::Method, so that our get_system_id method
# is implemented in the SystemInfo interface, which is under the System module.
#
# Implementing this, we would first add the method to our $modules struct maintaining the API heirarchy;
#
#  $modules => {
#	       System => {
#			 SystemInfo => {
#				       get_system_id => 0
#
# Analogous to:
#
#  $modules => {
#	       Module => {
#			 Interface => {
#				      Method => parameters
#
# A value of 0 is used for get_system_id as the method prototype takes no parameters.  For methods taking a single
# parameter, we would use the value of the required parameter name, for methods taking numerous parameters, we would
# use a hash containing a key for each parameter. 
#
# Our method is then created as an invocation to the private _request method setting the value of the module,
# interface and method arguments as per the API reference. i.e.
#
#  module 	=> 'System'
#  interface  	=> 'SystemInfo'
#  method	=> 'get_system_id'
#
# Which is intuitively translated into the implementation below;
# 
#  sub get_cluster_enabled_state {
#	my $self	= shift;
#	return $self->_request(module => 'System', interface => 'Cluster', method => 'get_cluster_enabled_state');
#  }
#

sub _request {
	my ($self, %args)= @_;
	$args{module}	and exists $modules->{$args{module}}					or return 'Request error: unknown module name: "'.$args{module}.'"';
	$args{interface}and exists $modules->{$args{module}}->{$args{interface}}		or return "Request error: unknown interface name for module $args{module}: \"$args{interface}\"";
	$args{method}	and exists $modules->{$args{module}}->{$args{interface}}->{$args{method}}or return "Request error: unknown method name for module $args{module} and interface $args{interface}: \"$args{method}\"";

	my @params = ();

	if ($modules->{$args{module}}->{$args{interface}}->{$args{method}}) {

		foreach my $arg (keys %{$args{data}}) {

			if (ref $modules->{$args{module}}->{$args{interface}}->{$args{method}} eq 'HASH') {
				exists $modules->{$args{module}}->{$args{interface}}->{$args{method}}->{$arg}
												or croak "Request error: method $args{method} for interface $args{interface} in module $args{module} requires " .
										  		"mandatory data parameter \"$modules->{$args{module}}->{$args{interface}}->{$args{method}}->{$arg}\"";
				push @params, SOAP::Data->name($arg => $args{data}{$arg});
			}
			else {
				$arg eq $modules->{$args{module}}->{$args{interface}}->{$args{method}}
												or croak "Request error: method $args{method} for interface $args{interface} in module $args{module} requires " .
												  "mandatory data parameter \"$modules->{$args{module}}->{$args{interface}}->{$args{method}}\"";
				push @params, SOAP::Data->name(%{$args{data}});
			}
		}
	}

	$self->_set_uri($args{module}, $args{interface});
	my $method	= $args{method};
	my $query	= $self->{_client}->$method(@params);
	$query->fault	and confess('SOAP call failed: ', $query->faultstring());
	$self->_unset_uri();
	return $query->result;
}

sub __get_timestamp {
	my %ts;
	@ts{qw(year month day hour minute second)} = ((localtime(time))[5,4,3,2,1,0]);
	$ts{year}+=1900;
	$ts{month}++;

	foreach (keys %ts) {
		$ts{$_} = __process_timestamp($ts{$_})
	}
	
	return %ts
}

sub __process_timestamp {
	my $time_stamp	= shift;
	return (__zero_fill($time_stamp->{year}) . '-' .
		__zero_fill($time_stamp->{month}) . '-' .
		__zero_fill($time_stamp->{day}) . '-' .
		__zero_fill($time_stamp->{hour}) . '-' .
		__zero_fill($time_stamp->{minute}) . '-' .
		__zero_fill($time_stamp->{second}))
}

sub __process_statistics {
	my $statistics	= shift;

	my %stat_obj	= (timestamp => __process_timestamp($statistics->{time_stamp}));

	foreach (@{%{@{%{$statistics}->{statistics}}[0]}->{statistics}}) {
		my $type			= %{$_}->{type};
		$stat_obj{stats}{$type}		= ((%{$_}->{value}{high})<<32)|(abs %{$_}->{value}{low});
	}
	
	return %stat_obj
}

sub __process_pool_member_statistics {
	my $statistics	= shift;
	my %stat_obj;

	foreach (@{$statistics}) {
		my $node	= %{@{%{$_}->{statistics}}[0]}->{member}->{address}.':'.%{@{%{$_}->{statistics}}[0]}->{member}->{port};
		$stat_obj{$node} = {__process_statistics($_)};
	}
	
	return %stat_obj
}

sub __zero_fill {
	my $val = shift; 
	return ($val < 10 ? '0' . $val : $val)
}

#sub _mutator_request {
#	my ($self, %args)=@_;
#	$args{module}	&& exists $mutators->{$args{module}}
#}

=head3 get_system_information

Return a SystemInformation struct containing the identifying attributes of the operating system.
The struct information is described below;

	Member					Type		Description
	----------				----------	----------
	system_name				String		The name of the operating system implementation.
	host_name				String		The host name of the system.
	os_release				String		The release level of the operating system.
	os_machine				String		The hardware platform CPU type.
	os_version				String		The version string for the release of the operating system.
	platform				String		The platform of the device.
	product_category			String 		The product category of the device.
	chassis_serial				String		The chassis serial number.
	switch_board_serial			String 		The serial number of the switch board.
	switch_board_part_revision		String 		The part revision number of the switch board.
	host_board_serial			String 		The serial number of the host motherboard.
	host_board_part_revision		String 		The part revision number of the host board.
	annunciator_board_serial		String 		The serial number of the annuciator board.
	annunciator_board_part_revision		String 		The part revision number of the annunciator board. 

=cut

sub get_system_information {
	my $self	= shift;
	return $self->_request(module => 'System', interface => 'SystemInfo', method => 'get_system_information');
}

=head3 get_cluster_list ()

Gets a list of the cluster names.

=cut

sub get_cluster_list {
	my $self	= shift;
	return $self->_request(module => 'System', interface => 'Cluster', method => 'get_list');
}

=head3 get_failover_mode ()

Gets the current fail-over mode that the device is running in. 

=cut

sub get_failover_mode {
	my $self	= shift;
	return $self->_request(module => 'System', interface => 'Failover', method => 'get_failover_mode');
}

=head3 get_failover_state ()

Gets the current fail-over state that the device is running in. 

=cut

sub get_failover_state {
	my $self	= shift;
	return $self->_request(module => 'System', interface => 'Failover', method => 'get_failover_state');
}

=head3 get_cluster_enabled_state ()

Gets the cluster enabled states. 

=cut

sub get_cluster_enabled_state {
	my $self	= shift;
	return $self->_request(module => 'System', interface => 'Cluster', method => 'get_cluster_enabled_state');
}

=head3 save_configuration ($filename)

	$ic->save_configuration('backup.ucs');

	# is equivalent to

	$ic->save_configuration('backup');
	
	# Not specifying a filename will use today's date in the
	# format YYYYMMDD as the filename.

	$ic->save_configuration();

	# is equivalent to

	$ic->save_configuration('today');
	

Saves the current configurations on the target device.  

This method takes a single optional parameter; the filename to which the configuration should be saved.  The file
extension B<.ucs> will be suffixed to the filename if missing from the supplied filename.

Specifying no optional filename parameter or using the filename B<today> will use the current date as the filename
of the saved configuration file in the format B<YYYYMMDD>.

=cut

sub save_configuration {
	my ($self,$filename)	= @_;

	if (($filename eq 'today') or ($filename eq '')) {
		$filename = __get_timestamp();
	}

	$self->_request(module => 'System', interface => 'ConfigSync', method => 'save_configuration', data => { filename => $filename, save_flag => 'SAVE_FULL'});

	return 1	
}

=head3 get_interface_list ()

	my @interfaces = $ic->get_interface_list();

Retuns an ordered list of all interfaces on the target device.

=cut

sub get_interface_list {
	my $self	= shift;
	return sort @{$self->_request(module => 'Networking', interface => 'Interfaces', method => 'get_list')}
}

=head3 get_interface_statistics ($interface)

Returns all statistics for the specified interface as a InterfaceStatistics object.  Unless you specifically
require access to the raw object, consider using B<get_interface_statistics_stringified> for a pre-parsed hash 
in an easy-to-digest format.

=cut

sub get_interface_statistics {
	my ($self, $inet)=@_;
	return $self->_request(module => 'Networking', interface => 'Interfaces', method => 'get_statistics', data => { interfaces => [$inet] })
}

=head3 get_interface_statistics_stringified ($interface)

	my $inet	= ($ic->get_interface_list())[0];
	my %stats       = $ic->get_interface_statistics_stringified($inet);

	print "Interface: $inet - Bytes in: $stats{stats}{STATISTIC_BYTES_IN} - Bytes out: STATISTIC_BYTES_OUT";

Returns all statistics for the specified interface as a hash having the following structure;

	{
	timestamp	=> 'YYYY-MM-DD-hh-mm-ss',
	stats		=> 	{
				statistic_1	=> value
				...
				statistic_n	=> value
				}
	}

Where the keys of the stats hash are the names of the statistic types defined in a InterfaceStatistics object.
Refer to the official API documentation for the exact structure of the InterfaceStatistics object.

=cut

sub get_interface_statistics_stringified {
	my ($self, $inet)=@_;
	return __process_statistics($self->get_interface_statistics($inet))
}

=head3 get_vs_list ()

	my @virtuals	= $ic->get_vs_list();

Returns an array of all defined virtual servers.

=cut

sub get_vs_list {
	my $self	= shift;
	return @{$self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_list')};
}

=head3 get_vs_destination ($virtual_server)

	my $destination	= $ic->get_vs_destination($vs);

Returns the destination of the specified virtual server in the form ipv4_address%route_domain:port.

=cut

sub get_vs_destination {
	my ($self, $vs)	= @_;
	my $destination	= @{$self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_destination', data => {virtual_servers => [$vs]})}[0];
	return $destination->{address}.':'.$destination->{port}
}

=head3 get_vs_enabled_state ($virtual_server)

	print "Virtual server $vs is in state ",$ic->get_vs_enabled_state($vs),"\n";

Return the enabled state of the specified virtual virtual server.

=cut

sub get_vs_enabled_state {
	my ($self, $vs)	= @_;
	return @{$self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_enabled_state', data => {virtual_servers => [$vs]})}[0];
}

=head3 get_vs_all_statistics ()

Returns the traffic statistics for all configured virtual servers.  The statistics are returned as 
VirtualServerStatistics struct hence this method is useful where access to raw statistical data is required.

For parsed statistic data, see B<get_vs_statistics_stringified>.

For specific information regarding data and units of measurement for statistics methods, please see the B<Notes> section.

=cut

sub get_vs_all_statistics {
	my ($self, %args)= @_;
	return $self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_all_statistics');
}

=head3 get_vs_statistics ($virtual_server)

	my $statistics = $ic->get_vs_statistics($vs);

Returns all statistics for the specified virtual server as a VirtualServerStatistics object.  Consider using get_vs_statistics_stringified
for accessing virtual server statistics in a pre-parsed hash structure.	

For specific information regarding data and units of measurement for statistics methods, please see the B<Notes> section.

=cut

sub get_vs_statistics {
	my ($self, $vs)	= @_;
	return $self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_statistics', data => {virtual_servers => [$vs]});
}

=head3 get_vs_statistics_stringified ($virtual_server)

	my $statistics = $ic->get_vs_statistics_stringified($vs);

	foreach (sort keys %{$stats{stats}}) {
		print "$_: $stats{stats}{$_}\n";
	}

Returns all statistics for the specified virtual server as a multidimensional hash (hash of hashes).  The hash has the following structure:

	{
		timestamp	=> 'yyyy-mm-dd-hh-mm-ss',
		stats		=> {
					statistic_1	=> value,
					statistic_2	=> value,
					...
					statistic_n	=> value
				}
	}

This function accepts a single parameter; the virtual server for which the statistics are to be returned.

For specific information regarding data and units of measurement for statistics methods, please see the B<Notes> section.

=cut

sub get_vs_statistics_stringified {
	my ($self, $vs)	= @_;
	return __process_statistics($self->get_vs_statistics($vs));
}

=head3 get_default_pool_name ($virtual_server)

	print "Virtual Server: $virtual_server\nDefault Pool: ", 
		$ic->get_default_pool_name($virtual_server), "\n";

Returns the default pool names for the specified virtual server.

=cut

sub get_default_pool_name {
	my ($self, $vs)=@_;
	return $self->_request(module => 'LocalLB', interface => 'VirtualServer', method => 'get_default_pool_name', data => {virtual_servers => [$vs]})
}

=head3 get_pool_list ()

	print join " ", ($ic->get_pool_list());

Returns a list of all pools in the target system.

=cut

sub get_pool_list {
	my $self	= shift;
	return @{$self->_request(module => 'LocalLB', interface => 'Pool', method => 'get_list')};
}

=head3 get_pool_members ($pool)

	foreach my $pool ($ic->get_pool_list()) {
		print "\n\n$pool:\n";

		foreach my $member ($ic->get_pool_members($pool)) {
			print "\t$member\n";
		}
	}

Returns a list of the pool members for the specified pool.  This method takes one mandatory parameter; the name of the pool.

Pool member are returned in the format B<IP_address:service_port>.

=cut 

sub get_pool_members {
	my ($self, $pool)= @_;
	my @members;
	foreach (@{@{$self->__get_pool_members($pool)}[0]}) {push @members, (%{$_}->{address}.':'.%{$_}->{port})}
	return @members;
}

sub __get_pool_members {
	my ($self, $pool)= @_;
	return $self->_request(module => 'LocalLB', interface => 'Pool', method => 'get_member', data => {pool_names => [$pool]});
}

=head3 get_pool_statistics ($pool)

	my %stats = $ic->get_pool_statistics($pool);

Returns the statistics for the specified pool as a PoolStatistics object.  For pre-parsed pool statistics consider using
the B<get_pool_statistics_stringified> method.

=cut

sub get_pool_statistics {
	my ($self, $pool)= @_;
	return $self->_request(module => 'LocalLB', interface => 'Pool', method => 'get_statistics', data => {pool_names => [$pool]});
}

=head3 get_pool_statistics_stringified ($pool)

	my %stats = $ic->get_pool_statistics_stringified($pool);
	print "Pool $pool bytes in: $stats{stat}{STATISTIC_SERVER_SIDE_BYTES_OUT}";

Returns a hash containing all pool statistics for the specified pool in a delicious, easily digestable and improved formula.

=cut

sub get_pool_statistics_stringified {
	my ($self, $pool)= @_;
	return __process_statistics($self->get_pool_statistics($pool));
}

=head3 get_pool_member_statistics ($pool)

Returns all pool member statistics for the specified pool as an array of MemberStatistics objects.  Unless you feel like 
playing with Data::Dumper on a rainy Sunday afternoon, consider using B<get_pool_member_statistics_stringified> method.

=cut

sub get_pool_member_statistics {
	my ($self, $pool)= @_;
	
	return $self->_request(module => 'LocalLB', interface => 'PoolMember', method => 'get_statistics', data => {
		pool_names	=> [$pool],
		members		=> $self->__get_pool_members($pool) });
}

=head3 get_pool_member_statistics_stringified ($pool)

	my %stats = $ic->get_pool_member_statistics_stringified($pool);

	print "Member\t\t\t\tRequests\n",'-'x5,"\t\t\t\t",'-'x5,"\n";
	
	foreach my $member (sort keys %stats) {
		print "$member\t\t$stats{$member}{stats}{STATISTIC_TOTAL_REQUESTS}\n";
	}

	# Prints a list of requests per pool member

Returns a hash containing all pool member statistics for the specified pool.  The hash has the following
structure;

	member_1 => 	{
			timestamp	=> 'YYYY-MM-DD-hh-mm-ss',
			stats		=>	{
						statistics_1	=> value
						...
						statistic_n	=> value
						}
			}
	member_2 =>	{
			...
			}
	member_n =>	{
			...
			}

Each pool member is specified in the form ipv4_address%route_domain:port.

=cut

sub get_pool_member_statistics_stringified {
	my ($self, $pool)= @_;
	return __process_pool_member_statistics($self->get_pool_member_statistics($pool))
}

=head3 get_all_pool_member_statistics ($pool)

Returns all pool member statistics for the specified pool.  This method is analogous to the B<get_pool_member_statistics()>
method and the two will likely be merged in a future release.

=cut

sub get_all_pool_member_statistics {
	my ($self, $pool)= @_;
	return $self->_request(module => 'LocalLB', interface => 'PoolMember', method => 'get_all_statistics', data => {pool_names => [$pool]});
}

=head3 get_node_list ()

	print join "\n", ($ic->get_node_list());

Returns a list of all configured nodes in the target system.

Nodes are returned as ipv4 addresses.

=cut 

sub get_node_list {
	my $self	= shift;
	return $self->_request(module => 'LocalLB', interface => 'NodeAddress', method => 'get_list');
}

=head3 get_screen_name ($node)

	foreach ($ic->get_node_list()) {
		print "Node: $_ (" . $ic->get_screen_name($_) . ")\n";
	}

Retuns the screen name of the specified node.

=cut 

sub get_screen_name {
	my ($self, %args)= @_;
	return $self->_request(module => 'LocalLB', interface => 'NodeAddress', method => 'get_screen_name', data => {node_addresses => $args{node_addresses}});
}

=head3 get_node_status ($node)

	$ic->get_node_status(

Returns the status of the specified node as a StatusObject struct.

For formatted node status information, see the B<get_node_status_as_string()> method.

=cut 

sub get_node_status {
	my ($self, $node)= @_;
	return $self->_request(module => 'LocalLB', interface => 'NodeAddress', method => 'get_object_status', data => {node_addresses => [$node]});
}

=head3 get_node_availability_status ($node)

Retuns the availability status of the node.

=cut 

sub get_node_availability_status {
	my ($self, $node)= @_;
	return $self->get_node_status_as_string($node,'availability_status');
}

=head3 get_node_enabled_status ($node)

Retuns the enabled status of the node.

=cut 

sub get_node_enabled_status {
	my ($self, $node)= @_;
	return $self->get_node_status_as_string($node,'enabled_status');
}

=head3 get_node_status_description ($node)

Returns a descriptive status of the specified node.

=cut 

sub get_node_status_description {
	my ($self, $node)= @_;
	return $self->get_node_status_as_string($node,'status_description');
}

=head3 get_node_status_as_string ($node)

Returns the node status as a descriptive string.

=cut 

sub get_node_status_as_string {
	my ($self, $node, $status_key)= @_;
	
	$status_key or ($status_key = 'status_description');
	
	return %{(@{$self->get_node_status($node)})[0]}->{$status_key};
}

=head3 get_node_monitor_status ($node)

Gets the current availability status of the specified node addresses. 

=cut 

sub get_node_monitor_status {
	my ($self, $node)= @_;
	return @{$self->_request(module => 'LocalLB', interface => 'NodeAddress', method => 'get_monitor_status', data => {node_addresses => [$node]})}[0];
}

=head3 get_node_statistics ($node)

Returns all statistics for the specified node.

=cut 

sub get_node_statistics {
	my ($self, $node)= @_;
	return $self->_request(module =>'LocalLB', interface => 'NodeAddress', method => 'get_statistics', data => {node_addresses => [$node]})
}

=head3 get_node_statistics_stringified

	my %stats = $ltm->get_node_statistics_stringified($node);

	foreach (sort keys %{stats{stats}}) {
		print "$_:\t$stats{stats}{$_}{high}\t$stats{stats}{$_}{low}\n";
	}

Returns a multidimensional hash containing all current statistics for the specified node.  The hash has the following structure:

	{
		timestamp	=> 'yyyy-mm-dd-hh-mm-ss',
		stats		=> {
					statistic_1	=> value,
					statistic_2	=> value,
					...
					statistic_n	=> value
				}
	}

This function accepts a single parameter; the node for which the statistics are to be returned.

For specific information regarding data and units of measurement for statistics methods, please see the B<Notes> section.

=cut

sub get_node_statistics_stringified {
	my ($self, $node)= @_;
	return __process_statistics($self->get_node_statistics($node));
	my $statistics	= $self->_request(module =>'LocalLB', interface => 'NodeAddress', method => 'get_statistics', data => {node_addresses => [$node]});
	my %stat_obj	= (timestamp => __process_timestamp($statistics->{time_stamp}));

	foreach (@{%{@{%{$statistics}->{statistics}}[0]}->{statistics}}) {
		my $type			= %{$_}->{type};
		$stat_obj{stats}{$type}{high}	= %{$_}->{value}{high};
		$stat_obj{stats}{$type}{low}	= %{$_}->{value}{low};
	}
	
	return %stat_obj
}

=head3 get_event_subscription

Returns all registered event subscriptions.

=cut 

sub get_event_subscription {
	my ($self, %args)=@_;
	return $self->_request(module => 'Management', interface => 'EventSubscription', method => 'get_list');
}

=head3 get_subscription_list

This method is an analog of B<get_event_subscription>

=cut 

sub get_subscription_list {
	my $self	= shift;
	return $self->_request(module => 'Management', interface => 'EventSubscription', method => 'get_list');
}

=head3 create_subscription_list (%args)

        my $subscription = $ic->create_subscription_list (
                                                name                            => 'my_subscription_name',
                                                url                             => 'http://company.com/my/eventnotification/endpoint,
                                                username                        => 'username',
                                                password                        => 'password',
                                                ttl                             => -1,
                                                min_events_per_timeslice        => 10,
                                                max_timeslice                   => 10
                                        );   

Creates an event subscription with the target system.  This method requires the following parameters:

=over 3

=item name 

A user-friendly name for the subscription.

=item url

The target URL endpoint for the event notification interface to send event notifications.

=item username

The basic authentication username required to access the URL endpoint.

=item password

The basic authentication password required to access the URL endpoint.

=item ttl

The time to live (in seconds) for this subscription. After the ttl is reached, the subscription
will be removed from the system. A value of -1 indicates an infinite life time.

=item min_events_per_timeslice

The minimum number of events needed to trigger a notification. If this value is 50, then this
means that when 50 events are queued up they will be sent to the notification endpoint no matter
what the max_timeslice is set to.

=item max_timeslice

This maximum time to wait (in seconds) before event notifications are sent to the notification
endpoint. If this value is 30, then after 30 seconds a notification will be sent with the events
in the subscription queue.

=back

=cut

sub create_subscription_list {
	my ($self, %args)=@_;
	$args{name}					or return 'Request error: missing "name" parameter';
	$args{url}					or return 'Request error: missing "url" parameter';	
	$args{username}					or return 'Request error: missing "username" parameter';	
	$args{password}					or return 'Request error: missing "password" parameter';	
	$args{ttl} =~ /^(-)?\d+$/			or return 'Request error: missing or incorrect "ttl" parameter';	
	$args{min_events_per_timeslice} =~ /^(-)?\d+$/	or return 'Request error: missing or incorrect "min_events_per_timeslice" parameter';	
	$args{max_timeslice} =~ /^(-)?\d+$/		or return 'Request error: missing or incorrect "max_timeslice" parameter';	
	@{$args{event_type}} > 0 			or return 'Request error: missing "event_type" parameter';

	foreach my $event (@{$args{event_type}}) {
		exists $event_types->{$event}		or return "Request error: unknown \"event_type\" parameter \"$event\"";
	}

	my $sub_detail_list= {
				name				=> $args{name},
				event_type_list			=> [@{$args{event_type}}],
				url				=> $args{url},
				url_credentials			=> {
									auth_mode	=> 'AUTHMODE_BASIC',
									username	=> $args{username},
									password	=> $args{password}
								},
				ttl				=> $args{ttl},
				min_events_per_timeslice	=> $args{min_events_per_timeslice},
				max_timeslice			=> $args{max_timeslice},
				enabled_state			=> 'STATE_ENABLED'
			};
	return $self->_request(module => 'Management', interface => 'EventSubscription', method => 'create', data => {sub_detail_list => [$sub_detail_list]});
}

=head1 NOTES

=head3 Statistic Methods

Within iControl, statistical values are a 64-bit unsigned integer represented as a B<Common::ULong64> object.
The ULong64 object is a stuct of two 32-bit values.  This representation is used as there is no native 
support for the encoding of 64-bit numbers in SOAP.

The ULong object has the following structure;

	({
		STATISTIC_NAME	=> {
				high	=> long
				low	=> long
			}
	}, bless Common::ULong64)

Where high is the unsigned 32-bit integer value of the high-order portion of the measured value and low is 
the unsigned 32-bit integer value of the low-order portion of the measured value.

In non-stringified statistic methods, these return values are ULong64 objects as returned by the iControl API.
In stringified statistic method calls, the values are processed on the client side into a local 64-bit representation
of the value using the following form.

	$value = ($high<<32)|$low;

Stringified method calls are guaranteed to return a correct localised 64-bit representation of the value.

It is the callers responsibility to convert the ULong struct for all other non-stringified statistic method calls.

=head1 AUTHOR

Luke Poskitt, E<lt>ltp@cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
