% TODO: explain better the fact that angular velocity of the state is
% GLOBAL rather than LOCAL

% build input and output manifolds
mx = manisetup(makeGenProduct('se3mat_e3_e3',makeSE3Mat(),makeRn(3),makeRn(3)));
%mx = manisetup(makeProduct(makeSE3Mat(),makeRn(3),makeRn(3))); 

mz = manisetup(makeSE3Mat());
mzr = manisetup(makeRot()); % only rotation, loss of position

mxt = makeSE3Mat(); % helper without the need of setup

% initial state and noise definition
x0 = mx.step(mx.exp([0,0,0,  0,1,0,   0,0,0,   0,0,0]'),[pi/2,0.2,0,  0,0,0,   0,0,0,   0,0,0]');
P0 = 0.5*eye(mx.alg);
Q = 0.01*eye(mx.alg); % process noi!se
R = 1e-3*eye(mz.alg); % measure noise
Rr = R(1:3,1:3); % only rotations

z0 = mz.exp([pi/2,0,0, 0,0.1,1]');
zobsval = zeros(16,200);

% costant se3 velocity
v0 = zeros(6,1);
v0(4) = 0.1;
v0(1) = 0.2;
zobsval(:,1) = z0;
lzobsval = zeros(mz.alg,size(zobsval,2));
lzobsval(:,1) = mz.log(z0);
for I=2:size(zobsval,2)
    v0(2) = sin(I/100);
    zobsval(:,I) = mz.step(zobsval(:,I-1),v0);
    lzobsval(:,I) = mz.log(zobsval(:,I));
end
zobs = @(t) zobsval(:,t);

wsigmax = ut_mweights2(mx.group,mx.alg,0.5);
wsigmax.sqrt = @svdsqrt; 

% observation is identity
% process is the integral
dt = 0.1;

% functions work in the real group space
f_fx = @(Tk,wk,vk) deal(mxt.step(Tk,[wk;vk]),wk,vk); % Xk = (Tk,wk,vk)
h_fx = @(Tk,wk,vk) Tk;
hr_fx = @(Tk,wk,vk) Tk(1:3,1:3);
tic
% loop
deltas = zeros(200,mz.alg);
states = zeros(size(deltas,1),mx.group);
lstates = zeros(size(deltas,1),mx.alg);
haspos = ones(200,1);
haspos(4:4:end) = 0;
haspos(5:4:end) = 0;
haspos(6:4:end) = 0;
usereduxspace = 0;

for L=1:size(deltas,1)
    states(L,:) = x0;
    lstates(L,:) = mx.log(x0);  % [ rodriguez(R) traslazione velocitàangolar velocitàlinear ]
    
    % check if x0s is available and reuse it below
    [xp,Pp] = manistatestep(mx,x0,P0,f_fx,Q,wsigmax);
    assert(size(xp,2)==1);
    if haspos(L) == 0 && usereduxspace        
        [zm,Czz,Cxz] = manievalh(mx,mzr,xp,Pp,hr_fx,wsigmax);
        assert(size(zm,2)==1);

        % Kalman update with observation noise (additive)    
        Pvv = Czz + Rr;
        K = Cxz/Pvv;
        P0 = (Pp - K * Pvv * K');
        
        fullobs_mat = mz.unpack( zobs(L)); % from SE3 16x1 to SE3 4x4
        
        deltar = mzr.delta(mzr.pack(fullobs_mat(1:3,1:3)),zm);
        x0 = mx.step(xp,(K*deltar')');
        delta = [deltar, NaN,NaN,NaN]; % ONLY for viz
    else       
        [zm,Czz,Cxz] = manievalh(mx,mz,xp,Pp,h_fx,wsigmax);
        assert(size(zm,2)==1);
        
        % Kalman update with observation noise (additive)    
        if haspos(L) == 0
            % maximal noise except for the rotation part
            Rr = 1e10*ones(size(R));
            Rr(1:3,1:3) = R(1:3,1:3);
            Rr(1:3,4:6) = 0;
            Czz(1:3,4:6) = 0;
            Czz(4:6,1:3) = 0;
            Pvv = Czz + Rr;
            % zero out the observation (cannot use NaN)
            zc = mz.unpack(zobs(L));
            zc{1}(1:3,4) = 0;
            z = mz.pack(zc);            
        else
            Pvv = Czz + R;
            z = zobs(L);
        end
        assert(size(z,1) == mz.group);
        assert(size(z,2) == 1);
        K = Cxz/Pvv;
        %P0 = (eye(size(P0)) - K * Pvv * K') * P0;
        P0t = Pp - K*Pvv*K';
        delta = K*mz.delta(z,zm)';        
        
        if 1==0
            % in some manifolds we cannot sum directly the delta
            % check Christoph Hertzberg Information Fusion 2013
            % NOT IMPLEMENTED YET [x0,P0,x0s] = manirelsum(xp,delta,P0t);
        else
            x0 = mx.step(xp,delta);
            P0 = P0t;
        end
        
    end
    deltas(L,:) = delta;
end
%%
toc
figure(1)
subplot(3,1,1);
plot(deltas(:,1:3))
title('Deltas observation-prediction');
xlabel('sample');
subplot(3,1,2);
plot(deltas(:,4:6))
title('Deltas observation-prediction');
xlabel('sample');
subplot(3,1,3);
plot(sum(deltas.^2,2));
title('Norm of error');
xlabel('sample');
figure(2)
plot(states(10:end,:))
title('All states as matrix');

%% Latency estimation
dd = zeros(1,6);
for J=1:6
    figure(2+J);
    dd(J) = finddelay(lstates(J,:),lzobsval(:,J));

    plot([lstates(J,:)';lzobsval(:,J)]);
end
disp('delay')
dd
disp('error')
sqrt(meannonan(deltas.^2,1))'
