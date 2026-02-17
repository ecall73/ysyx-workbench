#include <stdio.h>

struct rational
{
    int p;
    int q;
};

int gcd(int a, int b)
{
    if (b == 0)
        return a > 0 ? a : -a;
    else
        return gcd(b, a % b);
}

struct rational make_rational(int p, int q)
{
    struct rational r;
    int g;
    if (q < 0)
    {
        p = -p;
        q = -q;
    }
    g = gcd(p, q);
    r.p = p / g;
    r.q = q / g;
    return r;
}

struct rational add_rational(struct rational a, struct rational b)
{
    return make_rational(a.p * b.q + b.p * a.q, a.q * b.q);
}

struct rational sub_rational(struct rational a, struct rational b)
{
    return make_rational(a.p * b.q - b.p * a.q, a.q * b.q);
}

struct rational mul_rational(struct rational a, struct rational b)
{
    return make_rational(a.p * b.p, a.q * b.q);
}

struct rational div_rational(struct rational a, struct rational b)
{
    return make_rational(a.p * b.q, a.q * b.p);
}

void print_rational(struct rational r)
{
    if (r.q == 1)
        printf("%d\n", r.p);
    else
        printf("%d/%d\n", r.p, r.q);
}

int main(void)
{
    struct rational a = make_rational(1, 6);
    struct rational b = make_rational(-1, 8);
    print_rational(add_rational(a, b));
    print_rational(sub_rational(a, b));
    print_rational(mul_rational(a, b));
    print_rational(div_rational(a, b));

    return 0;
}