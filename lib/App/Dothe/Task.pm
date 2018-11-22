package App::Dothe::Task;

use 5.20.0;
use warnings;

use Moose;

use Log::Any qw($log);
use Types::Standard qw/ ArrayRef InstanceOf /;
use Type::Tiny;
use List::AllUtils qw/ min pairmap /;
use Ref::Util qw/ is_arrayref is_hashref /;

use Template::Mustache;

use experimental qw/
    signatures
    postderef
/;

use Path::Tiny;
use File::Wildcard;

has name => (
    is       => 'ro',
    required => 1,
);

has cmds => (
    is => 'ro',
    lazy => 1,
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        commands => 'elements',
    },
);

has raw_sources => (
    is	    => 'ro',
    default => sub { [] },
    init_arg => 'sources',
);

has raw_generates => (
    is	    => 'ro',
    default => sub { [] },
    init_arg => 'generates',
);


has sources => (
    is => 'ro',
    init_arg => undef,
    lazy => 1,
    default => sub($self) { 
        $self->vars->{sources} = $self->expand_files( $self->raw_sources )
    },
);

has generates => (
    is => 'ro',
    init_arg => undef,
    lazy => 1,
    default => sub { 
        $_[0]->vars->{generates} = $_[0]->expand_files( $_[0]->raw_generates )
    },
);

sub expand_files($self, $list ) {
    $list = [ $list ] unless ref $list;

    [ 
    map { File::Wildcard->new( path=> $_ )->all } 
    map { s!\*\*!/!gr }
    map { $self->render( $_, $self->vars ) }
    @$list ]
}


has tasks => (
    is	    => 'ro',
    required => 1,
);



sub latest_source_mod($self) {
    return min map { -M "".$_ } $self->sources->@*;
}

sub latest_generate_mod($self) {
    return min map { -M "".$_ } $self->generates->@*;
}

sub is_uptodate ($self) {
    return 0 if $self->tasks->force;

    my $source = $self->latest_source_mod;
    my $gen = $self->latest_generate_mod;

    return ( $gen and $source >= $gen );
};

has raw_vars => (
    is	    => 'ro',
    isa 	=> 'HashRef',
    init_arg => 'vars',
    default => sub($self) {
        +{}
    },
);

has vars => (
    is => 'ro',
    lazy => 1,
    isa => 'HashRef',
    builder => '_build_vars',
    init_arg => undef,
);


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
    my %vars = $self->tasks->vars->%*; 

    %vars = ( 
        %vars, 
        pairmap { $a => $self->render( $b, \%vars ) } $self->raw_vars->%* 
    );

    return \%vars;
}

has foreach => (
    is	    => 'ro',
    isa 	=> 'Str',
);

sub foreach_vars($self) {
    my $foreach = $self->foreach or return +{};

    return map { +{ item => $_ } } $self->vars->{$foreach}->@*;
}

has deps => (
    is	    => 'ro',
    isa 	=> 'ArrayRef',
    default => sub {
        []
    },
);

sub dependency_tree($self, $graph = undef ) {
    require Graph::Directed;

    $graph ||= Graph::Directed->new;

    return $graph
        if $graph->get_vertex_attribute( $self->name, 'done' );

    $graph->set_vertex_attribute( $self->name, 'done', 1 );

    for my $dep ( $self->deps->@* ) {
        $graph->add_edge( $dep => $self->name );
        $self->tasks->task($dep)->dependency_tree($graph);
    }

    return $graph;
}

sub dependencies($self) {
    return grep { $_ ne $self->name } $self->dependency_tree->topological_sort;
}

before run => sub ($self) {
    $log->infof( "running task %s", $self->name );
};

before run => sub($self) {
    my @deps = $self->dependencies;

    $self->tasks->task($_)->run for @deps;
};

sub run($self) {

    if ( $self->is_uptodate ) {
        $log->infof( '%s is up-to-date', $self->name );
        return;
    }

    my $vars = $self->vars;

        for my $entry ( $self->foreach_vars ) {
    for my $command ( $self->commands ) {

            my $vars = { $self->vars->%*, %$entry };
            my $processed = Template::Mustache->render( $command, $vars );

            $log->debug( "vars", $vars );
            $log->infof( "> %s", $processed );
            system $processed or next;

            die "command failed, aborting\n";
        }
    }

}

1;
