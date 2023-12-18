A = imread('out.ppm');
A = imread('verif_out.ppm');
A = imread('veri_gold_out.ppm');
imshow(A)

B = imread('/afs/ir/users/p/a/parthiv/public/ee271_vect/vec_271_01_sv_short_ref.ppm');
imshow(B)

B = imread('/afs/ir/users/p/a/parthiv/public/ee271_vect/vec_271_01_sv_ref.ppm');
C = abs(A - B);
find(C)
imshow(C*255)

[x, y, z] = ind2sub(size(C), 159936)