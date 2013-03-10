use strict;
use warnings;
package Test::Warnings;
# ABSTRACT: Test for warnings and the lack of them

use parent 'Exporter';
use Test::Builder;
use Class::Method::Modifiers;

our @EXPORT_OK = qw(allow_warnings allowing_warnings had_no_warnings);
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

$SIG{__WARN__} = sub {
    my $msg = shift;
    warn $msg;

    if (not $warnings_allowed
        or (ref $warnings_allowed eq 'ARRAY'
            and not grep { __is_regexp($_) and $msg =~ $_ } @$warnings_allowed)
    )
    {
        $forbidden_warnings_found++;
    }
};

if ($Test::Builder::VERSION >= 0.88)
{
    # monkeypatch Test::Builder::done_testing:
    # check for any forbidden warnings, and record that we have done so
    # so we do not check again via END
    Class::Method::Modifiers::install_modifier('Test::Builder',
        before => done_testing => sub {
            # only do this at the end of all tests, not at the end of a subtest
            if (not _builder()->parent)
            {
                local $Test::Builder::Level = $Test::Builder::Level + 3;
                had_no_warnings('no (unexpected) warnings (via done_testing)');
                $done_testing_called = 1;
            }
        },
    );
}

END {
    if (not $no_end_test
        and not $done_testing_called
        # skip this if there is no plan and no tests were run (e.g.
        # compilation tests of this module!)
        and (_builder->expected_tests or ref(_builder) ne 'Test::Builder')
        and _builder->current_test > 0
    )
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        had_no_warnings('no (unexpected) warnings (via END block)');
    }
}

# setter - takes no arg, true, false, or list of patterns
sub allow_warnings(;$)
{
    # no args - treat as allow_warnings(true)
    return $warnings_allowed = 1 if not @_;

    if (my @patterns = grep { __is_regexp($_) } @_)
    {
        $warnings_allowed = [ @patterns ];
        return @patterns;
    }

    # simple case - boolean argument
    $warnings_allowed = $_[0];
}

# getter - returns true, false, or list of patterns
sub allowing_warnings()
{
    ref $warnings_allowed eq 'ARRAY'
        ? @$warnings_allowed
        : $warnings_allowed
}

# call at any time to assert no (unexpected) warnings so far
sub had_no_warnings(;$)
{
    _builder()->ok(!$forbidden_warnings_found, shift || 'no (unexpected) warnings');
}

sub __is_regexp
{
    $^V < 5.009005 ? ref(shift) eq 'Regexp' : re::is_regexp(shift);
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

=head1 FUNCTIONS

The following functions are available for import (not included by default; you
can also get all of them by importing the tag C<:all>):

=over

=item * C<< allow_warnings([bool | list]) >>

When passed a true value, or no value at all, subsequent warnings will not
result in a test failure; when passed a false value, subsequent warnings will
result in a test failure.

When passed one or more patterns (of the form qr/.../), warnings matching this
pattern(s) will not cause subsequent C<had_no_warnings> tests to fail.
Calling this function twice will overwrite previous values (to add more, do
C<< allow_warnings( allowing_warnings, qr/.../, qr/.../) >>).

Initial value is C<false>.

=item * C<allowing_warnings>

Returns whether we are currently allowing warnings (set by C<allow_warnings>
as described above): returns a boolean (if all warnings are allowed or
disallowed), or returns the list of regexes of warnings that will be allowed.

=item * C<< had_no_warnings(<optional test name>) >>

Tests whether there have been any warnings so far, not preceded by an
C<allowing_warnings> call.  It is run
automatically at the end of all tests, but can also be called manually at any
time, as often as desired.

=back

=head1 OTHER OPTIONS

=over

=item * C<:all> - Imports all functions listed above

=item * C<:no_end_test> - Disables the addition of a C<had_no_warnings> test via END (but if you don't want to do this, you probably shouldn't be loading this module at all!)

=back

=head1 TO DO (i.e. FUTURE FEATURES, MAYBE)

=over

=item * C<< allow_warnings(qr/.../) >> - allow some warnings and not others

=item * C<< warning_is, warning_like etc... >> - inclusion of some
L<Test::Warn>-like functionality for testing the content of warnings, but
closer to a L<Test::Fatal>-like syntax

=item * more sophisticated handling in subtests - if we save some state on the
L<Test::Builder> object itself, we can allow warnings in a subtest and then
the state will revert when the subtest ends, as well as check for warnings at
the end of every subtest via C<done_testing>.

=back

=head1 SUPPORT

Bugs may be submitted through L<https://rt.cpan.org/Public/Dist/Display.html?Name=Test-Warnings>.
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

L<Test::NoWarnings>

L<Test::FailWarnings>

L<blogs.perl.org: YANWT|http://blogs.perl.org/users/ether/2013/03/yanwt-yet-another-no-warnings-tester.html>

=cut
