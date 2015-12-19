use strict;
use warnings;
package Test::Warnings;
# ABSTRACT: Test for warnings and the lack of them
# KEYWORDS: testing tests warnings
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.023';

use parent 'Exporter';
use Test::Builder;

our @EXPORT_OK = qw(
    allow_warnings allowing_warnings
    had_no_warnings
    warnings warning
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

my $warnings_allowed;
my $forbidden_warnings_found;
my $done_testing_called;
my $no_end_test;

sub import
{
    # END block will check for this status
    my @symbols = grep { $_ ne ':no_end_test' } @_;
    $no_end_test = (@symbols != @_);

    __PACKAGE__->export_to_level(1, @symbols);
}

# for testing this module only!
my $tb;
sub _builder(;$)
{
    if (not @_)
    {
        $tb ||= Test::Builder->new;
        return $tb;
    }

    $tb = shift;
}

my $_orig_warn_handler = $SIG{__WARN__};
$SIG{__WARN__} = sub {
    if ($warnings_allowed)
    {
        Test::Builder->new->note($_[0]);
    }
    else
    {
        $forbidden_warnings_found++;
        goto &$_orig_warn_handler if $_orig_warn_handler;

        if ($_[0] =~ /\n$/) {
            warn $_[0];
        } else {
            require Carp;
            Carp::carp($_[0]);
        }
    }
};

sub warnings(&)
{
    my $code = shift;
    my @warnings;
    local $SIG{__WARN__} = sub {
        push @warnings, shift;
    };
    $code->();
    @warnings;
}

sub warning(&)
{
    my @warnings = &warnings(@_);
    return @warnings == 1 ? $warnings[0] : \@warnings;
}

if (Test::Builder->can('done_testing'))
{
    # monkeypatch Test::Builder::done_testing:
    # check for any forbidden warnings, and record that we have done so
    # so we do not check again via END

    no strict 'refs';
    my $orig = *{'Test::Builder::done_testing'}{CODE};
    no warnings 'redefine';
    *{'Test::Builder::done_testing'} = sub {
        # only do this at the end of all tests, not at the end of a subtest
        my $builder = _builder;
        my $in_subtest_sub = $builder->can('in_subtest');
        if (not $no_end_test
            and not ($in_subtest_sub ? $builder->$in_subtest_sub : $builder->parent))
        {
            local $Test::Builder::Level = $Test::Builder::Level + 3;
            had_no_warnings('no (unexpected) warnings (via done_testing)');
            $done_testing_called = 1;
        }

        $orig->(@_);
    };
}

END {
    if (not $no_end_test
        and not $done_testing_called
        # skip this if there is no plan and no tests have been run (e.g.
        # compilation tests of this module!)
        and (_builder->expected_tests or _builder->current_test > 0)
    )
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        had_no_warnings('no (unexpected) warnings (via END block)');
    }
}

# setter
sub allow_warnings(;$)
{
    $warnings_allowed = @_ || defined $_[0] ? $_[0] : 1;
}

# getter
sub allowing_warnings() { $warnings_allowed }

# call at any time to assert no (unexpected) warnings so far
sub had_no_warnings(;$)
{
    _builder->ok(!$forbidden_warnings_found, shift || 'no (unexpected) warnings');
}

1;
__END__

=pod

=head1 SYNOPSIS

    use Test::More;
    use Test::Warnings;

    pass('yay!');
    done_testing;

emits TAP:

    ok 1 - yay!
    ok 2 - no (unexpected) warnings (via done_testing)
    1..2

and:

    use Test::More tests => 3;
    use Test::Warnings 0.005 ':all';

    pass('yay!');
    like(warning { warn "oh noes!" }, qr/^oh noes/, 'we warned');

emits TAP:

    ok 1 - yay!
    ok 2 - we warned
    ok 3 - no (unexpected) warnings (via END block)
    1..3

=head1 DESCRIPTION

If you've ever tried to use L<Test::NoWarnings> to confirm there are no warnings
generated by your tests, combined with the convenience of C<done_testing> to
not have to declare a
L<test count|Test::More/I love it-when-a-plan-comes-together>,
you'll have discovered that these two features do not play well together,
as the test count will be calculated I<before> the warnings test is run,
resulting in a TAP error. (See C<examples/test_nowarnings.pl> in this
distribution for a demonstration.)

This module is intended to be used as a drop-in replacement for
L<Test::NoWarnings>: it also adds an extra test, but runs this test I<before>
C<done_testing> calculates the test count, rather than after.  It does this by
hooking into C<done_testing> as well as via an C<END> block.  You can declare
a plan, or not, and things will still Just Work.

It is actually equivalent to:

    use Test::NoWarnings 1.04 ':early';

as warnings are still printed normally as they occur.  You are safe, and
enthusiastically encouraged, to perform a global search-replace of the above
with C<use Test::Warnings;> whether or not your tests have a plan.

It can also be used as a replacement for L<Test::Warn>, if you wish to test
the content of expected warnings; read on to find out how.

=head1 FUNCTIONS

The following functions are available for import (not included by default; you
can also get all of them by importing the tag C<:all>):

=head2 C<< allow_warnings([bool]) >> - EXPERIMENTAL - MAY BE REMOVED

When passed a true value, or no value at all, subsequent warnings will not
result in a test failure; when passed a false value, subsequent warnings will
result in a test failure.  Initial value is C<false>.

When warnings are allowed, any warnings will instead be emitted via
L<Test::Builder::note|Test::Builder/Output>.

=head2 C<allowing_warnings> - EXPERIMENTAL - MAY BE REMOVED

Returns whether we are currently allowing warnings (set by C<allow_warnings>
as described above).

=head2 C<< had_no_warnings(<optional test name>) >>

Tests whether there have been any warnings so far, not preceded by an
C<allowing_warnings> call.  It is run
automatically at the end of all tests, but can also be called manually at any
time, as often as desired.

=head2 C<< warnings( { code } ) >>

Given a code block, runs the block and returns a list of all the
(not previously allowed via C<allow_warnings>) warnings issued within.  This
lets you test for the presence of warnings that you not only would I<allow>,
but I<must> be issued.  Testing functions are not provided; given the strings
returned, you can test these yourself using your favourite testing functions,
such as L<Test::More::is|Test::More/is> or L<Test::Deep::cmp_deeply|Test::Deep/cmp_deeply>.

You can use this construct as a replacement for
L<Test::Warn::warnings_are|Test::Warn/warnings_are>:

    is_deeply(
        [ warnings { ... } ],
        [
            'warning message 1',
            'warning message 2',
        ],
        'got expected warnings',
    );

or, to replace L<Test::Warn::warnings_like|Test::Warn/warnings_like>:

    cmp_deeply(
        [ warnings { ... } ],
        bag(    # ordering of messages doesn't matter
            re(qr/warning message 1/),
            re(qr/warning message 2/),
        ),
        'got expected warnings (in any order)',
    );

Warnings generated by this code block are I<NOT> propagated further. However,
since they are returned from this function with their filename and line
numbers intact, you can re-issue them yourself immediately after calling
C<warnings(...)>, if desired.

Note that C<use Test::Warnings 'warnings'> will give you a C<warnings>
subroutine in your namespace (most likely C<main>, if you're writing a test),
so you (or things you load) can't subsequently do C<< warnings->import >> --
it will result in the error: "Not enough arguments for
Test::Warnings::warnings at ..., near "warnings->import"".  To work around
this, either use the fully-qualified form (C<Test::warnings>) or make your
calls to the C<warnings> package first.

=head2 C<< warning( { code } ) >>

Same as C<< warnings( { code } ) >>, except a scalar is always returned - the
single warning produced, if there was one, or an arrayref otherwise -- which
can be more convenient to use than C<warnings()> if you are expecting exactly
one warning.

However, you are advised to capture the result from C<warning()> into a temp
variable so you can dump its value if it doesn't contain what you expect.
e.g. with this test:

    like(
        warning { foo() },
        qr/^this is a warning/,
        'got a warning from foo()',
    );

if you get two warnings (or none) back instead of one, you'll get an
arrayref, which will result in an unhelpful test failure message like:

    #   Failed test 'got a warning from foo()'
    #   at t/mytest.t line 10.
    #                   'ARRAY(0xdeadbeef)'
    #     doesn't match '(?^:^this is a warning)'

So instead, change your test to:

    my $warning = warning { foo() };
    like(
        $warning,
        qr/^this is a warning/,
        'got a warning from foo()',
    ) or diag 'got warning(s): ', explain($warning);

=head1 IMPORT OPTIONS

=head2 C<:all>

Imports all functions listed above

=head2 C<:no_end_test>

Disables the addition of a C<had_no_warnings> test
via C<END> or C<done_testing>

=head1 CAVEATS

=for stopwords smartmatch TODO irc

Sometimes new warnings can appear in Perl that should B<not> block
installation -- for example, smartmatch was recently deprecated in
perl 5.17.11, so now any distribution that uses smartmatch and also
tests for warnings cannot be installed under 5.18.0.  You might want to
consider only making warnings fail tests in an author environment -- you can
do this with the L<if> pragma:

    use if $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING}, 'Test::Warnings';

In future versions of this module, when interfaces are added to test the
content of warnings, there will likely be additional sugar available to
indicate that warnings should be checked only in author tests (or TODO when
not in author testing), but will still provide exported subs.  Comments are
enthusiastically solicited - drop me an email, write up an RT ticket, or come
by C<#perl-qa> on irc!

=for stopwords Achtung

B<Achtung!>  This is not a great idea:

    sub warning_like(&$;$) {
        my ($code, $pattern, $name) = @_;
        like( &warning($code), $pattern, $name );
    }

    warning_like( { ... }, qr/foo/, 'foo appears in the warning' );

If the code in the C<{ ... }> is going to warn with a stack trace with the
arguments to each subroutine in its call stack (for example via C<Carp::cluck>),
the test name, "foo appears in the warning" will itself be matched by the
regex (see F<examples/warning_like.t>).  Instead, write this:

  like( warning { ... }, qr/foo/, 'foo appears in the warning' );

=head1 TO DO (or: POSSIBLE FEATURES COMING IN FUTURE RELEASES)

=over

=item * C<< allow_warnings(qr/.../) >> - allow some warnings and not others

=for stopwords subtest subtests

=item * more sophisticated handling in subtests - if we save some state on the
L<Test::Builder> object itself, we can allow warnings in a subtest and then
the state will revert when the subtest ends, as well as check for warnings at
the end of every subtest via C<done_testing>.

=item * sugar for making failures TODO when testing outside an author
environment

=back

=head1 SEE ALSO

=for stopwords YANWT

=for :list
* L<Test::NoWarnings>
* L<Test::FailWarnings>
* L<blogs.perl.org: YANWT (Yet Another No-Warnings Tester)|http://blogs.perl.org/users/ether/2013/03/yanwt-yet-another-no-warnings-tester.html>
* L<strictures> - which makes all warnings fatal in tests, hence lessening
the need for special warning testing
* L<Test::Warn>
* L<Test::Fatal>

=cut
