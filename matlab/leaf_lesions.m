% leaf_lesions.m - label every leaf pixel as one of five tissue classes
%
%   healthy    a* <= A_GREEN and S >= S_MIN
%   sooty      L* < 22
%   powdery    S < S_MIN and L* >= 40
%   chlorotic  A_GREEN < a* < 8 and b* >= 14
%   necrotic   everything else
%
% A_GREEN and S_MIN start at -8 and 0.20 and are loosened towards the
% leaf's own green (median of its clearly green pixels), so a dull or
% dusty leaf is not called diseased all over. Each class is then cleaned
% with an opening and a closing.
function M = leaf_lesions(den, mask)

A_GREEN  = -8;    S_MIN = 0.20;
L_SOOTY  = 22;    L_POWDER = 40;   B_YELLOW = 14;

lab = rgb2lab(den);
hsv = rgb2hsv(den);
L = lab(:,:,1);  a = lab(:,:,2);  b = lab(:,:,3);
S = hsv(:,:,2);

green = mask & atan2d(b, a) >= 95 & atan2d(b, a) < 175 & hypot(a, b) > 4 & L >= L_SOOTY;
if nnz(green) > 0.10 * nnz(mask)
    A_GREEN = max(A_GREEN, min(-2, median(a(green)) + 5));
    S_MIN   = min(S_MIN, max(0.08, 0.5 * median(S(green))));
end

healthy   = mask & a <= A_GREEN & S >= S_MIN & L >= L_SOOTY;
sooty     = mask & L < L_SOOTY;
powdery   = mask & S < S_MIN & L >= L_POWDER & ~sooty;
chlorotic = mask & ~healthy & ~sooty & ~powdery & ...
            a > A_GREEN & a < 8 & b >= B_YELLOW & S >= S_MIN;
necrotic  = mask & ~(healthy | sooty | powdery | chlorotic);

se = strel('disk', 2);
chlorotic = imclose(imopen(chlorotic, se), se) & mask;
necrotic  = imclose(imopen(necrotic,  se), se) & mask;
powdery   = imclose(imopen(powdery,   se), se) & mask;
sooty     = imclose(imopen(sooty,     se), se) & mask;

lesion  = (chlorotic | necrotic | powdery | sooty) & mask;
healthy = mask & ~lesion;

M = struct('a_green', A_GREEN, 's_min', S_MIN, ...
           'healthy', healthy, 'chlorotic', chlorotic, 'necrotic', necrotic, ...
           'powdery', powdery, 'sooty', sooty, 'lesion', lesion, 'mask', mask);
end
