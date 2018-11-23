package App::Dothe;
# ABSTRACT: YAML-based build system

use 5.20.0;
use warnings;

use MooseX::App::Simple;

use YAML::XS qw/ LoadFile /;
use App::Dothe::Task;

use Log::Any::Adapter;
Log::Any::Adapter->set('Stdout', log_level => 'info' );

use List::AllUtils qw/ pairmap /;

use Text::Template;

use experimental qw/ signatures postderef /;

option debug => (
    is => 'ro',
    documentation => 'enable debugging logs',
    default => 0,
    isa => 'Bool',
    trigger => sub {
        Log::Any::Adapter->set('Stdout', log_level => 'debug' );
    },
);

option force => (
    is => 'ro',
    documentation => 'force the tasks to be run',
    default => 0,
    isa => 'Bool',
);

parameter target => (
    is => 'ro',
    required => 1,
);

has raw_vars => (
    is	    => 'ro',
    isa 	=> 'HashRef',
    init_arg => 'vars',
    default => sub($self) {
        $self->config->{vars} || {}
    },
);

has vars => (
    is => 'ro',
    lazy => 1,
    isa => 'HashRef',
    builder => '_build_vars',
    init_arg => undef,
);

use Ref::Util qw/ is_arrayref is_hashref /;

sub render($self,$template,$vars) {
    if( is_arrayref $template ) {
        return [ map { $self->render($_,$vars) } @$template ];
    }

    if( is_hashref $template ) {
        return { pairmap { $a => $self->render($b,$vars) } %$template }
    }

    return $self->template($template)->fill_in(HASH => $vars );
}

sub _build_vars($self) {
    my %vars; 

    %vars = ( 
        %vars, 
        pairmap { $a => $self->render( $b, \%vars ) } $self->raw_vars->%* 
    );

    return \%vars;
}

has tasks => (
    is => 'ro',
    lazy => 1,
    traits => [ 'Hash' ],
    default => sub($self) { +{} },
);

sub task($self,$name) {
    return $self->{tasks}{$name} ||= App::Dothe::Task->new( 
        name => $name, tasks => $self, $self->config->{tasks}{$name}->%* );
}

has config => (
    is => 'ro',
    lazy => 1,
    default => sub($self) { LoadFile( './Taskfile.yml' ) },
);

sub run( $self ) {

    if ( my $code = $self->config->{code} ) {
        eval join '', 'package App::Dothe::Sandbox;', @$code;
    }

    $self->task($self->target)->run;

}

sub template ($self,$source) {
    return Text::Template->new( TYPE => 'STRING', DELIMITERS => [ '{{', '}}' ], 
        SOURCE => $source );
}

1;
