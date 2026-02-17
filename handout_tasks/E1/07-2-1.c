#include <stdio.h>
#include <math.h>

struct complex_struct {
    double x, y;
};

double real_part(struct complex_struct z)
{
    return z.x;
}

double img_part(struct complex_struct z)
{
    return z.y;
}

double magnitude(struct complex_struct z)
{
    return sqrt(z.x * z.x + z.y * z.y);
}

double angle(struct complex_struct z)
{
    return atan2(z.y, z.x);
}

struct complex_struct make_from_real_img(double x, double y)
{
    struct complex_struct z;
    z.x = x;
    z.y = y;
    return z;
}

struct complex_struct make_from_mag_ang(double r, double A)
{
    struct complex_struct z;
    z.x = r * cos(A);
    z.y = r * sin(A);
    return z;
}

struct complex_struct add_complex(struct complex_struct z1, struct complex_struct z2)
{
    return make_from_real_img(real_part(z1) + real_part(z2),
                  img_part(z1) + img_part(z2));
}

struct complex_struct sub_complex(struct complex_struct z1, struct complex_struct z2)
{
    return make_from_real_img(real_part(z1) - real_part(z2),
                  img_part(z1) - img_part(z2));
}

struct complex_struct mul_complex(struct complex_struct z1, struct complex_struct z2)
{
    return make_from_mag_ang(magnitude(z1) * magnitude(z2),
                 angle(z1) + angle(z2));
}

struct complex_struct div_complex(struct complex_struct z1, struct complex_struct z2)
{
    return make_from_mag_ang(magnitude(z1) / magnitude(z2),
                 angle(z1) - angle(z2));
}

void print_complex(struct complex_struct z)
{
    if (z.x == 0 && z.y == 0)
        printf("0.0");
    else if (z.x == 0)
        printf("%fi", z.y);
    else if (z.y == 0)
        printf("%f", z.x);
    else if (z.y > 0)
        printf("%f+%fi", z.x, z.y);
    else
        printf("%f%fi", z.x, z.y);
}

int main()
{
    struct complex_struct z1 = make_from_real_img(1.0, 2.0);
    struct complex_struct z2 = make_from_real_img(3.0, -4.0);
    struct complex_struct z3 = make_from_real_img(0.0, 5.0);
    struct complex_struct z4 = make_from_real_img(-2.0, 0.0);
    struct complex_struct z5 = make_from_real_img(0.0, 0.0);
    struct complex_struct z6 = make_from_real_img(-1.0, -1.0);
    
    printf("z1 = "); print_complex(z1); printf("\n");
    printf("z2 = "); print_complex(z2); printf("\n");
    printf("z3 = "); print_complex(z3); printf("\n");
    printf("z4 = "); print_complex(z4); printf("\n");
    printf("z5 = "); print_complex(z5); printf("\n");
    printf("z6 = "); print_complex(z6); printf("\n");
    
    printf("z1 + z2 = "); print_complex(add_complex(z1, z2)); printf("\n");
    printf("z1 - z2 = "); print_complex(sub_complex(z1, z2)); printf("\n");
    printf("z1 * z2 = "); print_complex(mul_complex(z1, z2)); printf("\n");
    printf("z1 / z2 = "); print_complex(div_complex(z1, z2)); printf("\n");
    
    struct complex_struct z7 = make_from_mag_ang(2.0, 34159/2);
    printf("z7 (r=2.0, A=π/2) = "); print_complex(z7); printf("\n");
    
    return 0;
}