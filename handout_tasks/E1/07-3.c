#include <math.h>
#include <stdio.h>

enum coordinate_type { RECTANGULAR, POLAR };

struct complex_struct {
    enum coordinate_type t;
    double a, b;
};

double real_part(struct complex_struct z) {
    if (z.t == RECTANGULAR)
        return z.a;
    else  // POLAR
        return z.a * cos(z.b);
}

double img_part(struct complex_struct z) {
    if (z.t == RECTANGULAR)
        return z.b;
    else  // POLAR
        return z.a * sin(z.b);
}

double magnitude(struct complex_struct z) {
    if (z.t == RECTANGULAR)
        return sqrt(z.a * z.a + z.b * z.b);
    else  // POLAR
        return z.a;
}

double angle(struct complex_struct z) {
    if (z.t == RECTANGULAR)
        return atan2(z.b, z.a);
    else  // POLAR
        return z.b;
}

int main()
{
    struct complex_struct z1 = {RECTANGULAR, 3.0, 4.0};
    struct complex_struct z2 = {POLAR, 10.0, atan2(4.0, 3.0)};

    printf("z1: real = %f, imag = %f, mag = %f, ang = %f rad\n",
           real_part(z1), img_part(z1), magnitude(z1), angle(z1));

    printf("z2: real = %f, imag = %f, mag = %f, ang = %f rad\n",
           real_part(z2), img_part(z2), magnitude(z2), angle(z2));

    return 0;
}