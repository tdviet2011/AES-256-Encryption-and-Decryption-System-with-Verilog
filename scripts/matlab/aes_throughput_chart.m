%% aes_throughput_chart.m
% Bieu do truc log: tang so luong block ma hoa tu 1 den 10 trieu (10^7),
% xem TOC DO ma hoa (throughput, Mbps) va SAI SO toc do do bien doi tan so
% clock khi tong hop FPGA, cung voi TY LE CHINH XAC theo so luong block.
%
% Day la MO HINH LY THUYET tinh tu so cycle/block da do duoc trong
% testbench (khong phai chay sim thuc 10 trieu lan - qua lau).
% Muon so lieu toc do THAT, phai tong hop (synthesis) tren FPGA cu the
% va doc bao cao timing (.rpt) de lay Fmax thuc te.

clear; clc; close all;

%% ---- Thong so cac top module (cycles / block, do trong testbench) ----
module_names = {'aes256\_enc\_dec\_top (unmasked)', ...
                'aes256\_enc\_dec\_top\_cached (key cache)', ...
                'aes256\_masked\_top (masked)', ...
                'aes256\_masked\_top\_mk (masked + BRAM key)'};
cycles_per_block = [50, 38, 1017, 1032];   % tu bang verification results

% Khoang tan so clock gia dinh sau tong hop FPGA (vi du chung, CHUA do thuc te)
% -> day la nguon "sai so" toc do: Fmax thay doi theo FPGA/constraint/placement
f_min_MHz = 50;    % tan so thap (constraint chat, FPGA nho/cu)
f_typ_MHz = 100;   % tan so "danh gia" trung binh
f_max_MHz = 200;   % tan so cao (FPGA nhanh, da toi uu timing)

bits_per_block = 128;

%% ---- Truc so block: 1 -> 10^7, chia deu theo log ----
N = logspace(0, 7, 50);   % 10^0 den 10^7 block, 50 diem

figure('Color','w','Position',[100 100 1100 650]);

%% ---- Subplot 1: Throughput vs so block (loglog, co bang sai so) ----
subplot(2,1,1);
colors = lines(numel(module_names));
hold on;
for m = 1:numel(module_names)
    cyc = cycles_per_block(m);

    % Thoi gian (s) = N * cyc / f ; Throughput (Mbps) = N*bits / thoi_gian /1e6
    t_typ = N .* cyc ./ (f_typ_MHz*1e6);
    thr_typ = (N .* bits_per_block) ./ t_typ / 1e6;

    t_min_f = N .* cyc ./ (f_min_MHz*1e6);   % f thap -> thoi gian lau -> thr thap
    thr_low = (N .* bits_per_block) ./ t_min_f / 1e6;

    t_max_f = N .* cyc ./ (f_max_MHz*1e6);   % f cao -> thr cao
    thr_high = (N .* bits_per_block) ./ t_max_f / 1e6;

    % Vung sai so (do bien doi Fmax 50-200MHz) + duong "typ" o giua
    fill([N, fliplr(N)], [thr_low, fliplr(thr_high)], colors(m,:), ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    loglog(N, thr_typ, '-', 'Color', colors(m,:), 'LineWidth', 1.8, ...
        'DisplayName', module_names{m});
end
set(gca, 'XScale', 'log', 'YScale', 'log');
grid on;
xlabel('So luong block ma hoa (block, truc log)');
ylabel('Toc do ma hoa (Mbps)');
title('Toc do ma hoa theo so block (vung mau = sai so do Fmax = 50-200MHz)');
legend('Location', 'southoutside', 'Orientation', 'horizontal', 'FontSize', 8);
xlim([1, 1e7]);

%% ---- Subplot 2: Ty le chinh xac vs so block ----
subplot(2,1,2);
% AES la thuat toan tat dinh (deterministic): voi 1 key/data_in cho truoc,
% ket qua luon dung 100% bat ke ma hoa bao nhieu block (da kiem chung
% 440/440 tren vector NIST + ngau nhien). Khong co "nhieu" lam giam do
% chinh xac theo so luong, nen duong nay la hang 100%.
accuracy_pct = 100 * ones(size(N));
semilogx(N, accuracy_pct, 'LineWidth', 2, 'Color', [0.20 0.60 0.35]);
hold on;
yline(100, '--', 'Color', [0.6 0.6 0.6]);
ylim([90 102]);
grid on;
xlabel('So luong block ma hoa (block, truc log)');
ylabel('Ty le chinh xac (%)');
title('Ty le chinh xac ma hoa/giai ma theo so block (thuat toan tat dinh -> luon 100%)');
xlim([1, 1e7]);

sgtitle('AES-256 core: Toc do va Do chinh xac khi tang so block ma hoa', ...
    'FontWeight', 'bold');

saveas(gcf, 'aes_throughput_chart.png');
fprintf('Da luu bieu do: aes_throughput_chart.png\n');

fprintf('\n--- Vi du so lieu tai N = 1e6 block ---\n');
for m = 1:numel(module_names)
    cyc = cycles_per_block(m);
    t_typ = 1e6 * cyc / (f_typ_MHz*1e6);
    thr_typ = (1e6*bits_per_block)/t_typ/1e6;
    fprintf('  %-45s  %8.2f Mbps (Fmax=100MHz)\n', module_names{m}, thr_typ);
end
