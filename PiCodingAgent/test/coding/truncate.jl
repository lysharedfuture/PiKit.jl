@testset "truncate" begin
    @test CA.format_size(100) == "100B"
    @test CA.format_size(1536) == "1.5KB"
    @test CA.format_size(2 * 1024 * 1024) == "2.0MB"

    text = join(["line$i" for i in 1:2500], "\n")
    r = CA.truncate_head(text)
    @test r.truncated && r.truncated_by == "lines"
    @test r.output_lines == 2000
    @test r.total_lines == 2500
    @test occursin("line2000", r.content) && !occursin("line2001", r.content)

    tail = CA.truncate_tail(text; max_lines=10)
    @test tail.truncated && tail.output_lines == 10
    @test last(split(tail.content, '\n')) == "line2500"

    long_first = repeat("x", 60 * 1024) * "\nsecond"
    h = CA.truncate_head(long_first)
    @test h.first_line_exceeds_limit && isempty(h.content)

    # UTF-8 boundary in tail truncation
    s = "é" ^ 1000
    t = CA.truncate_tail(s; max_lines=1, max_bytes=101)
    @test sizeof(t.content) <= 101
    @test !occursin('\ufffd', t.content)

    tl = CA.truncate_line(repeat("a", 600))
    @test tl.was_truncated
    @test endswith(tl.text, "... [truncated]")
end
