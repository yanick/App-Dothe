package App::Dothe::Tasks;

use 5.20.0;
use warnings;

use Moose;

use YAML::XS qw/ LoadFile /;
use App::Dothe::Task;

use List::AllUtils qw/ pairmap /;

use experimental qw/
    signatures
    postderef
/;

has force => (
    is => 'ro',
    lazy => 1,
    default => 0,
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

    Template::Mustache->render( $template, $vars );
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
    default => sub($self) {
        return { pairmap {
            $a => App::Dothe::Task->new( name => $a, %$b, tasks => $self );
        }
            $self->config->{tasks}->%*
        }
    },
    handles => {
        task => 'get'
    },
);

has config => (
    is => 'ro',
    lazy => 1,
    default => sub($self) { LoadFile( './Taskfile.yml' ) },
);

sub run( $self, @tasks ) {

    $self->task($_)->run( ) for @tasks;

}

1;
