%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Multi Sensor-based Distributed Bayesian Estimator
% This code is for distributed bayesian estimator for target positioning and tracking
% (1) Target: Static target with unknown position
% (2) Sensors: Binary sensor with only 0 or 1 measurement
% (3) Strategy: (3.1) Observation Exchange strategy (Neighbourhood or Global-Exchange)
%               (3.2) Probability Map Consensus strategy (single step or multi-step)
%% 2015 June; All Copyright Reserved
% 3/17/16
% modified the code for the final version of ACC16 paper.
% add comparison with concensus and centralized filters

clear; clc; close all

%% %%%%%%%%%%%%%%%%%%%%%% General Setup %%%%%%%%%%%%%%%%%%%%%%
max_EstStep = 1; % max step
ConsenStep=10;

Selection = 1; % select the motion of agents and target
switch Selection
    case 1,  r_move= 0; tar_move=0;
    case 2,  r_move= 0; tar_move=1;
    case 3,  r_move= 1; tar_move=0;
    case 4,  r_move= 1; tar_move=1;
    otherwise, error('No selection.');
end

top_select = 1; % select the communication topology

% the set of robots whose pdf will be drawn
sim_r_idx = [1,3,5];

NumOfRobot = 6;
x_set = [20,40,60,80,60,40];
y_set = [50,20,20,50,80,80];

save_file = 0; % choose whether to save simulation results

%% %%%%%%%%%%%%%%%%%%%%%%%%%% Setup for multiple trials %%%%%%%%%%%%%%%%%%%
%% Field Setup
fld = struct();
trial_num = 10; % number of trials to run
% generate random target position (just generate once and use them afterwards)
% rnd_tar_pos(1,:) = randi([5,fld.x-5],1,trial_num);
% rnd_tar_pos(2,:) = randi([5,fld.y-5],1,trial_num);
fld.x = 100; fld.y = 100;  % Field size
fld.tx_set = [68, 55, 41, 10, 75, 35, 60, 72, 14, 16];
fld.ty_set = [55, 49, 86, 77, 71, 9, 11, 13, 77, 90];
[ptx,pty] = meshgrid(1:fld.x,1:fld.y);
pt = [ptx(:),pty(:)];

trial_cnt = 10;
sim = struct();
sim.r_move = r_move;
sim.tar_move = tar_move;
sim.max_EstStep = max_EstStep;
sim.ConsenStep = ConsenStep;
sim.NumOfRobot = NumOfRobot;
sim.r_init_pos_set = [x_set;y_set];
sim.sim_r_idx = sim_r_idx;
sim.trial_num = trial_num;
sim.top_select = top_select;


while (trial_cnt <= trial_num)
    %% Target Setup
    fld.map = ones(fld.x,fld.y)/(fld.x*fld.y);
    [xpt,ypt] = meshgrid(1:fld.x,1:fld.y);
    fld.traj = []; % trajectory of traget
    
    fld.tx = fld.tx_set(trial_cnt);
    fld.ty = fld.ty_set(trial_cnt);
    
    %% Probability Map Consensus setup
    ConsenFigure=0; % if 1, draw the concensus steps
    
    %% Multi-Robot Setup
    for i=1:NumOfRobot
        rbt(i).traj = [];
        rbt(i).x = x_set(i); % sensor position.x
        rbt(i).y = y_set(i); % sensor position.x
        rbt(i).map = ones(fld.x,fld.y);
        rbt(i).map = rbt(i).map/sum(sum(rbt(i).map));
        rbt(i).prob = zeros(fld.x,fld.y);
        rbt(i).entropy = zeros(1,max_EstStep);
        for j = 1:NumOfRobot
            rbt(i).rbt(j).used = []; % save the observations times that have been used for updating
        end
    end
    
    % binary sensor model
    sigmaVal=(fld.x/10)^2+(fld.y/10)^2; % covariance matrix for the sensor
    k_s = 2*pi*sqrt(det(sigmaVal)); % normalizing factor
    s_psi = 1/2*eye(2)/sigmaVal; % psi for the sensor
    % robot colors
    rbt(1).color = 'r';
    rbt(2).color = 'g';
    rbt(3).color = 'y';
    rbt(4).color = 'c';
    rbt(5).color = 'm';
    rbt(6).color = 'w';
    
    %% Communication structure
    switch top_select 
        case 1
            rbt(1).top(1).neighbour=[2,6];
            rbt(2).top(1).neighbour=1;
            rbt(3).top(1).neighbour=4;
            rbt(4).top(1).neighbour=[3,5];
            rbt(5).top(1).neighbour=4;
            rbt(6).top(1).neighbour=1;
            
            rbt(1).top(2).neighbour=0;
            rbt(2).top(2).neighbour=3;
            rbt(3).top(2).neighbour=2;
            rbt(4).top(2).neighbour=0;
            rbt(5).top(2).neighbour=6;
            rbt(6).top(2).neighbour=5;
            
        case 2
            rbt(1).top(1).neighbour=6;
            rbt(2).top(1).neighbour=0;
            rbt(3).top(1).neighbour=5;
            rbt(4).top(1).neighbour=0;
            rbt(5).top(1).neighbour=3;
            rbt(6).top(1).neighbour=1;
            
            rbt(1).top(2).neighbour=2;
            rbt(2).top(2).neighbour=1;
            rbt(3).top(2).neighbour=0;
            rbt(4).top(2).neighbour=5;
            rbt(5).top(2).neighbour=4;
            rbt(6).top(2).neighbour=0;
            
            rbt(1).top(3).neighbour=0;
            rbt(2).top(3).neighbour=3;
            rbt(3).top(3).neighbour=2;
            rbt(4).top(3).neighbour=0;
            rbt(5).top(3).neighbour=6;
            rbt(6).top(3).neighbour=5;
    end
    
    %% Robot Buffer for Observation Exchange
    for i=1:NumOfRobot
        for j=1:NumOfRobot
            rbtBuffer{i}.rbt(j).x=[];
            rbtBuffer{i}.rbt(j).y=[];
            rbtBuffer{i}.rbt(j).z=[];
            rbtBuffer{i}.rbt(j).k=[];
            rbtBuffer{i}.rbt(j).prob=[];
            rbtBuffer{i}.rbt(j).map = {};% record the previously calculated map to reduce computation
        end
    end
    
    % initialize rbt_cons and rbt_cent
    % rbt_cons is robot structure used in consensus algorithm
    rbt_cons = rbt;
    % rbt_cons is robot structure used in centralized algorithm
    rbt_cent.map = rbt(1).map;
    rbt_cent.z = [];
    rbt_cent.prob = cell(NumOfRobot,1);
    
    %% Performance Metrics
    for i=1:NumOfRobot
        % ml estimate of target position
        rbt(i).ml_pos_dbf = zeros(2,max_EstStep);
        rbt_cons(i).ml_pos_cons = zeros(2,max_EstStep);
        
        % distance between ml estimate and true target position
        rbt(i).ml_err_dbf = zeros(max_EstStep,1);
        rbt_cons(i).ml_err_cons = zeros(max_EstStep,1);
        
        % covariance of target pdf
        rbt(i).pdf_cov_dbf = cell(max_EstStep,1);
        rbt_cons(i).pdf_cov_cons = cell(max_EstStep,1);
        
        % Frobenius norm of target pdf
        rbt(i).pdf_norm_dbf = zeros(max_EstStep,1);
        rbt_cons(i).pdf_norm_cons = zeros(max_EstStep,1);
        
        % entropy of target pdf
        rbt(i).ent_dbf = zeros(max_EstStep,1);
        rbt_cons(i).ent_cons = zeros(max_EstStep,1);
    end
    % only one centralized filter, not for each robot, so rbt_cent is one
    % single variable
    rbt_cent.ml_pos_cent = zeros(2,max_EstStep);
    rbt_cent.ml_err_cent = zeros(max_EstStep,1);
    rbt_cent.pdf_cov_cent = cell(max_EstStep,1);
    rbt_cent.pdf_norm_cent = zeros(max_EstStep,1);
    rbt_cent.ent_cent = zeros(max_EstStep,1);
    
    %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Bayesian Filter for Target Tracking
    count = 1; % time step
    while (1) %% Filtering Time Step
        disp(trial_cnt)
        fig_cnt = 0; % counter for figure
        
        % record robot and target trajectories
        for ii = 1:NumOfRobot
            rbt(ii).traj = [rbt(ii).traj,[rbt(ii).x;rbt(ii).y]]; % robot trajectory
            rbt_cons(ii).traj = rbt(ii).traj;
        end
        fld.traj = [fld.traj,[fld.tx;fld.ty]]; % target trajectory
        
        % Generate measurement and observation probability
        rbt_cent.z = [];
        for i=1:NumOfRobot % Robot Iteration
            rbt(i).z = sensorSim(rbt(i).x,rbt(i).y,fld.tx,fld.ty,sigmaVal);
            rbt_cons(i).z = rbt(i).z;
            rbt_cent.z = [rbt_cent.z;rbt(i).z];
        end
        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% Bayesian Updating
        % steps:
        % (1) send/receive and update stored observations up to time k-1
        % (2) observe and update the stored own observations at time k
        % (3) update probability map
        % (4) repeat step (1)
        
        if (Selection == 1) || (Selection == 3)
            % static target
            %% data transmission
            % (1) sending/receive
            % multi-step transmit of observation
            switch top_select
                case 1
                    if rem(count,2) == 1 % in odd round
                        top_idx = 1; % use topology 1
                    else
                        top_idx = 2; % use topology 2
                    end
                case 2
                    if rem(count,3) == 1 % in odd round
                        top_idx = 1; % use topology 1
                    elseif rem(count,3) == 2
                        top_idx = 2; % use topology 2
                    else
                        top_idx = 3; % use topology 2
                    end
            end
            
            tempRbtBuffer = rbtBuffer;
            for i=1:NumOfRobot % Robot Iteration
                % for information from neighbours to compare whether it is
                % latest
                for j=1:NumOfRobot
                    for t=rbt(i).top(top_idx).neighbour
                        if t == 0 % if no neighbors
                            continue
                        end
                        % note: communication only transmit the latest
                        % observation stored in each neighbor
                        if (~isempty(rbtBuffer{t}.rbt(j).k)) && (isempty(tempRbtBuffer{i}.rbt(j).k) || (tempRbtBuffer{i}.rbt(j).k < rbtBuffer{t}.rbt(j).k))
                            tempRbtBuffer{i}.rbt(j).x = rbtBuffer{t}.rbt(j).x;
                            tempRbtBuffer{i}.rbt(j).y = rbtBuffer{t}.rbt(j).y;
                            tempRbtBuffer{i}.rbt(j).z = rbtBuffer{t}.rbt(j).z;
                            tempRbtBuffer{i}.rbt(j).k = rbtBuffer{t}.rbt(j).k;
                            tempRbtBuffer{i}.rbt(j).prob = rbtBuffer{t}.rbt(j).prob;
                        end
                    end
                end
            end
            
            % return temperary buffer to robot buffer
            for i=1:NumOfRobot
                for j=1:NumOfRobot
                    rbtBuffer{i}.rbt(j).x = tempRbtBuffer{i}.rbt(j).x;
                    rbtBuffer{i}.rbt(j).y = tempRbtBuffer{i}.rbt(j).y;
                    rbtBuffer{i}.rbt(j).z = tempRbtBuffer{i}.rbt(j).z;
                    rbtBuffer{i}.rbt(j).k = tempRbtBuffer{i}.rbt(j).k;
                    rbtBuffer{i}.rbt(j).prob = tempRbtBuffer{i}.rbt(j).prob;
                end
            end
            
            % (2) observation
            % Observation of each robot
            for i=1:NumOfRobot
                % initialize the buffer
                rbtBuffer{i}.rbt(i).x=rbt(i).x;
                rbtBuffer{i}.rbt(i).y=rbt(i).y;
                rbtBuffer{i}.rbt(i).z=rbt(i).z;
                rbtBuffer{i}.rbt(i).k=count;
                if (~isempty(rbtBuffer{i}.rbt(i).k)) && (rbtBuffer{i}.rbt(i).z == 1)
                    rbtBuffer{i}.rbt(i).prob = sensorProb(rbtBuffer{i}.rbt(i).x,rbtBuffer{i}.rbt(i).y,fld.x,fld.y,sigmaVal);
                elseif ~isempty(rbtBuffer{i}.rbt(i).k) && (rbtBuffer{i}.rbt(i).z == 0)
                    rbtBuffer{i}.rbt(i).prob = 1 - sensorProb(rbtBuffer{i}.rbt(i).x,rbtBuffer{i}.rbt(i).y,fld.x,fld.y,sigmaVal);
                end
                
                % assign this probability to rbt_cons and rbt_cent to
                % save computation resource
                rbt_cons(i).prob = rbtBuffer{i}.rbt(i).prob;
                rbt_cent.prob{i} = rbtBuffer{i}.rbt(i).prob;
            end
            display(rbtBuffer{1}.rbt(1)),display(rbtBuffer{1}.rbt(2)),display(rbtBuffer{1}.rbt(3))
            display(rbtBuffer{1}.rbt(4)),display(rbtBuffer{1}.rbt(5)),display(rbtBuffer{1}.rbt(6))
            
            %% update by bayes rule
            % calculate probility of latest z
            for i=1:NumOfRobot % Robot Iteration
                for j=1:NumOfRobot
                    if (~isempty(rbtBuffer{i}.rbt(j).k)) && (~ismember(rbtBuffer{i}.rbt(j).k,rbt(i).rbt(j).used))
                        rbt(i).map=rbt(i).map.*rbtBuffer{i}.rbt(j).prob;
                        rbt(i).rbt(j).used = [rbt(i).rbt(j).used,rbtBuffer{i}.rbt(j).k];
                    end
                end
                rbt(i).map=rbt(i).map/sum(sum(rbt(i).map));
            end
        end
        
        %% %%%%%%%%%%%%%%  Consensus Method %%%%%%%%%%%%%%%%%%
        % steps:
        % (1) observe and update the probability map for time k
        % (2) send/receive the probability map for time k-1 from neighbors
        % (3) repeat step (1)
        % note: the steps are opposite to the DBF steps, which first exchange
        % info and then incorporate new observations. I still need to think
        % carefully which order is more reasonable. But for now, I think it's
        % better to present the consensused results in paper so that readers
        % will not get confused.
        
        % update using new observation
        if (Selection == 1) || (Selection == 3)
            % update probability map
            for i=1:NumOfRobot
                tmp_cons_map = rbt_cons(i).map.*rbt_cons(i).prob;
                rbt_cons(i).map = tmp_cons_map/sum(sum(tmp_cons_map));
            end
        end
        
        % consensus step
        % receive and weighted average neighboring maps
        for i=1:NumOfRobot % Robot Iteration
            rbtCon(i).map=rbt_cons(i).map;
        end
        
        for ConStep=1:ConsenStep % Consensus cycle
            if ConsenFigure==1
                fig_cnt = fig_cnt+1;
                h_cons = figure(fig_cnt);
                clf(h_cons);
            end
            for i=1:NumOfRobot % Robot Iteration
                if rbt(i).top(top_idx).neighbour == 0
                    neighNum = 1;
                elseif rbt(i).top(top_idx).neighbour > 0
                    neighNum = length(rbt(i).top(top_idx).neighbour)+1;
                end
                tempRbtCon(i).map = rbtCon(i).map;
                for t=rbt(i).top(top_idx).neighbour
                    if t ~= 0
                        tempRbtCon(i).map=tempRbtCon(i).map+rbtCon(t).map;
                    end
                end
                tempRbtCon(i).map=tempRbtCon(i).map/neighNum;
            end
            % plot local PDFs after concensus
            for i=1:NumOfRobot
                rbtCon(i).map=tempRbtCon(i).map;
                if ConsenFigure==1
                    figure(fig_cnt)
                    subplot(2,3,i); contourf((rbtCon(i).map)'); title(['Sensor ',num2str(i)]);
                    hold on;
                    for j=1:NumOfRobot
                        if i==j
                            plot(rbt(j).x, rbt(j).y, 's','Color',rbt(j).color,'MarkerSize',8,'LineWidth',3);
                        else
                            plot(rbt(j).x, rbt(j).y, 'p','Color',rbt(j).color, 'MarkerSize',8,'LineWidth',1.5);
                        end
                    end
                end
            end
        end
        for i=1:NumOfRobot % Robot Iteration
            rbt_cons(i).map=rbtCon(i).map;
        end
        
        %% %%%%%%%%%%%%%% Centralized BF %%%%%%%%%%%%%%%%%%
        % steps:
        % (1) receive all robots' observations
        % (2) update the probability map for time k
        % (3) repeat step (1)
        
        tmp_cent_map = rbt_cent.map;
        if (Selection == 1) || (Selection == 3)
            % update step
            for i = 1:NumOfRobot
                tmp_cent_map = tmp_cent_map.*rbt_cent.prob{i};
            end
            rbt_cent.map = tmp_cent_map/sum(sum(tmp_cent_map));
        end
        
        %% %%%%%%%%%%%% Computing Performance Metrics %%%%%%%%%%%%%%%%%%%        
        % ML error
        for i = 1:NumOfRobot
            % DBF
            [tmp_x1,tmp_y1] = find(rbt(i).map == max(rbt(i).map(:)));
            if length(tmp_x1) > 1
                tmp_idx = randi(length(tmp_x1),1,1);
            else
                tmp_idx = 1;
            end
            rbt(i).ml_dbf(:,count) = [tmp_x1(tmp_idx);tmp_y1(tmp_idx)];
            rbt(i).ml_err_dbf(count) = norm(rbt(i).ml_dbf(:,count)-[fld.tx;fld.ty]);
            
            % concensus
            [tmp_x2,tmp_y2] = find(rbt_cons(i).map == max(rbt_cons(i).map(:)));
            if length(tmp_x2) > 1
                tmp_idx2 = randi(length(tmp_x2),1,1);
            else
                tmp_idx2 = 1;
            end
            rbt_cons(i).ml_cons(:,count) = [tmp_x2(tmp_idx2);tmp_y2(tmp_idx2)];
            rbt_cons(i).ml_err_cons(count) = norm(rbt_cons(i).ml_cons(:,count)-[fld.tx;fld.ty]);
        end
        
        % centralized
        [tmp_x3,tmp_y3] = find(rbt_cent.map == max(rbt_cent.map(:)));
        if length(tmp_x3) > 1
            tmp_idx3 = randi(length(tmp_x3),1,1);
        else
            tmp_idx3 = 1;
        end
        rbt_cent.ml_cent(:,count) = [tmp_x3(tmp_idx3);tmp_y3(tmp_idx3)];
        rbt_cent.ml_err_cent(count) = norm(rbt_cent.ml_cent(:,count)-[fld.tx;fld.ty]);
        
        % Covariance of posterior pdf
        for i=1:NumOfRobot
            % DBF
            tmp_map1 = rbt(i).map;
            % this avoids the error when some grid has zeros probability
            tmp_map1(tmp_map1 <= realmin) = realmin;
            
            % compute covariance of distribution
            dif1 = pt' - [(1+fld.x)/2;(1+fld.y)/2]*ones(1,size(pt',2));
            cov_p1 = zeros(2,2);
            for jj = 1:size(pt',2)
                cov_p1 = cov_p1 + dif1(:,jj)*dif1(:,jj)'*tmp_map1(pt(jj,1),pt(jj,2));
            end
            rbt(i).pdf_cov{count} = cov_p1;
            rbt(i).pdf_norm_dbf(count) = norm(cov_p1,'fro');
            
            % concensus
            tmp_map2 = rbt_cons(i).map;
            % this avoids the error when some grid has zeros probability
            tmp_map2(tmp_map2 <= realmin) = realmin;
            
            % compute covariance of distribution
            dif2 = pt' - [(1+fld.x)/2;(1+fld.y)/2]*ones(1,size(pt',2));
            cov_p2 = zeros(2,2);
            for jj = 1:size(pt',2)
                cov_p2 = cov_p2 + dif2(:,jj)*dif2(:,jj)'*tmp_map2(pt(jj,1),pt(jj,2));
            end
            rbt_cons(i).pdf_cov_cons{count} = cov_p2;
            rbt_cons(i).pdf_norm_cons(count) = norm(cov_p2,'fro');
        end
        
        % centralized
        tmp_map3 = rbt_cent.map;
        % this avoids the error when some grid has zeros probability
        tmp_map3(tmp_map3 <= realmin) = realmin;
        
        % compute covariance of distribution
        dif3 = pt' - [(1+fld.x)/2;(1+fld.y)/2]*ones(1,size(pt',2));
        cov_p3 = zeros(2,2);
        for jj = 1:size(pt',2)
            cov_p3 = cov_p3 + dif3(:,jj)*dif3(:,jj)'*tmp_map3(pt(jj,1),pt(jj,2));
        end
        rbt_cent.pdf_cov_cent{count} = cov_p3;
        rbt_cent.pdf_norm_cent(count) = norm(cov_p3,'fro');
        
        % Entropy of posterior pdf
        %
        for i=1:NumOfRobot
            % DBF
            tmp_map1 = rbt(i).map;
            % this avoids the error when some grid has zeros probability
            tmp_map1(tmp_map1 <= realmin) = realmin;
            dis_entropy = -(tmp_map1).*log2(tmp_map1); % get the p*log(p) for all grid points
            rbt(i).entropy(count) = sum(sum(dis_entropy));
            
            % concensus
            tmp_map2 = rbt_cons(i).map;
            % this avoids the error when some grid has zeros probability
            tmp_map2(tmp_map2 <= realmin) = realmin;
            dis_entropy = -(tmp_map2).*log2(tmp_map2); % get the p*log(p) for all grid points
            rbt_cons(i).entropy(count) = sum(sum(dis_entropy));
        end
        % centralized
        tmp_map3 = rbt_cent.map;
        % this avoids the error when some grid has zeros probability
        tmp_map3(tmp_map3 <= realmin) = realmin;
        dis_entropy = -(tmp_map3).*log2(tmp_map3); % get the p*log(p) for all grid points
        rbt_cent.entropy(count) = sum(sum(dis_entropy));
        
        %}
        
        %% %%%%%%%%%%%%%% Plotting for simulation process %%%%%%%%%%%%%%%%%
        if count == max_EstStep
            %% LIFO-DBF
            %
            % plot figures for selected robots
            for k = sim_r_idx
                fig_cnt = fig_cnt+1;
                tmp_hd = figure (fig_cnt); % handle for plot of a single robot's target PDF
                clf(tmp_hd);
                shading interp
                contourf((rbt(k).map)','LineColor','none');
                load('MyColorMap','mymap')
                colormap(mymap);
                colorbar
                hold on;
                for j=1:NumOfRobot
                    % draw robot trajectory
                    if j==k
                        line_hdl = line(rbt(j).traj(1,:), rbt(j).traj(2,:));
                        set(line_hdl,'Marker','.','Color','r','MarkerSize',3,'LineWidth',2);
                        plot(rbt(j).traj(1,end), rbt(j).traj(2,end), 's','Color','r','MarkerSize',25,'LineWidth',3);
                    else
                        line_hdl = line(rbt(j).traj(1,:), rbt(j).traj(2,:));
                        set(line_hdl,'Marker','.','Color','g','MarkerSize',3,'LineWidth',2);
                        plot(rbt(j).traj(1,end), rbt(j).traj(2,end), 'p','Color','g','MarkerSize',25,'LineWidth',1.5);
                    end
                    
                    % draw traget trajectory
                    line_hdl = line(fld.traj(1,:), fld.traj(2,:));
                    set(line_hdl,'Marker','.','Color','k','MarkerSize',3,'LineWidth',2);
                    plot(fld.tx, fld.ty, 'k+','MarkerSize',25,'LineWidth',3);
                    set(gca,'fontsize',30)
                end
                xlabel(['Step=',num2str(count)],'FontSize',30);
            end
            %}
            
            %% Consensus
            % plot figures for selected robots
            %
            for k = sim_r_idx
                fig_cnt = fig_cnt+1;
                tmp_hd = figure (fig_cnt); % handle for plot of a single robot's target PDF
                clf(tmp_hd);
                shading interp
                contourf((rbt_cons(k).map)','LineColor','none');
                load('MyColorMap','mymap')
                colormap(mymap);
                colorbar
                hold on;
                for j=1:NumOfRobot
                    
                    % draw robot trajectory
                    if j==k
                        line_hdl = line(rbt(j).traj(1,:), rbt(j).traj(2,:));
                        set(line_hdl,'Marker','.','Color','r','MarkerSize',3,'LineWidth',2);
                        plot(rbt(j).traj(1,end), rbt(j).traj(2,end), 's','Color','r','MarkerSize',25,'LineWidth',3);
                    else
                        line_hdl = line(rbt(j).traj(1,:), rbt(j).traj(2,:));
                        set(line_hdl,'Marker','.','Color','g','MarkerSize',3,'LineWidth',2);
                        plot(rbt(j).traj(1,end), rbt(j).traj(2,end), 'p','Color','g','MarkerSize',25,'LineWidth',1.5);
                    end
                    
                    % draw target trajectory
                    line_hdl = line(fld.traj(1,:), fld.traj(2,:));
                    set(line_hdl,'Marker','.','Color','k','MarkerSize',3,'LineWidth',2);
                    plot(fld.tx, fld.ty, 'k+','MarkerSize',25,'LineWidth',3);
                    set(gca,'fontsize',30)
                end
                xlabel(['Step=',num2str(count)],'FontSize',30);
            end
            %}
            
            %% Centralized
            %
            % plot figures for central map
            fig_cnt = fig_cnt+1;
            tmp_hd = figure (fig_cnt); % handle for plot of a single robot's target PDF
            clf(tmp_hd);
            shading interp
            contourf((rbt_cent.map)','LineColor','none');
            load('MyColorMap','mymap')
            colormap(mymap);
            colorbar
            xlabel(['Step=',num2str(count)],'FontSize',30);
            
            hold on;
            
            % draw robot trajectory
            for j=1:NumOfRobot
                line_hdl = line(rbt(j).traj(1,:), rbt(j).traj(2,:));
                set(line_hdl,'Marker','.','Color','g','MarkerSize',3,'LineWidth',2);
                plot(rbt(j).traj(1,end), rbt(j).traj(2,end), 'p','Color','g','MarkerSize',25,'LineWidth',1.5);
            end
            
            % draw target trajectory
            line_hdl = line(fld.traj(1,:), fld.traj(2,:));
            set(line_hdl,'Marker','.','Color','k','MarkerSize',3,'LineWidth',2);
            plot(fld.tx, fld.ty, 'k+','MarkerSize',25,'LineWidth',3);
            set(gca,'fontsize',30)
            %}
        end
        
        % save changing pdf plots
        %{
        if (count == 1) || (count == 3) || (count == 5) || (count == 7) ||...
                (count == 10) || (count == 20) || (count == 30) || (count == 40)...
                || (count == 50) || (count == 60) || (count == 70) || (count == 80)...
                || (count == 90) || (count == 100)
            switch Selection2
                case 1,  tag = 'sta_sen_sta_tar';
                case 2,  tag = 'sta_sen_mov_tar';
                case 3,  tag = 'mov_sen_sta_tar';
                case 4,  tag = 'mov_sen_mov_tar';
            end
            %         file_name1 = sprintf('./figures/data_exchange_switch/%s_%d_%s',tag,count,datestr(now,1));
            %         saveas(hf1,file_name1,'fig')
            %         saveas(hf1,file_name1,'jpg')
            for k = sim_r_idx
                tmp_hf = figure(k+2);
                file_name2 = sprintf('./figures/data_exchange/%s_single_%d_%d_%s',tag,k,count,datestr(now,1));
                if save_file == 1
                    saveas(tmp_hf,file_name2,'fig')
                    saveas(tmp_hf,file_name2,'jpg')
                end
            end
        end
        %}
        
        %% %%%%%%%%%%%%%%% robots and target move %%%%%%%%%%%%%%%%%
        % in this code, they don't move
        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% Terminate Time Cycle
        count = count+1;
        disp(count);
        if count > max_EstStep
            break
        end
    end
    for i = 1:NumOfRobot
        sim(trial_cnt).rbt(i) = rbt(i);
        sim(trial_cnt).rbt_cons(i) = rbt_cons(i);
    end
    sim(trial_cnt).rbt_cent = rbt_cent;
    
    trial_cnt = trial_cnt+1;
end

%% %%%%%%%%%%%%%% performance metrics for all trials %%%%%%%%%%%%%%%%%
% overall simulation result
for jj = 1:trial_num
    for ii = 1:NumOfRobot
        % ml error
        sim_res.ml_err_dbf(ii,jj,:) = sim(jj).rbt(ii).ml_err_dbf;
        sim_res.ml_err_cons(ii,jj,:) = sim(jj).rbt_cons(ii).ml_err_cons;
        
        % norm of cov of pdf
        sim_res.pdf_norm_dbf(ii,jj,:) = sim(jj).rbt(ii).pdf_norm_dbf;
        sim_res.pdf_norm_cons(ii,jj,:) = sim(jj).rbt_cons(ii).pdf_norm_cons;
        
        % entropy of pdf
        sim_res.entropy_dbf(ii,jj,:) = sim(jj).rbt(ii).entropy;
        sim_res.entropy_cons(ii,jj,:) = sim(jj).rbt_cons(ii).entropy;
    end
    sim_res.ml_err_cent(jj,:) = sim(jj).rbt_cent.ml_err_cent;
    sim_res.pdf_norm_cent(jj,:) = sim(jj).rbt_cent.pdf_norm_cent;
    sim_res.entropy_cent(jj,:) = sim(jj).rbt_cent.entropy;
end

for ii = 1:NumOfRobot
    % ml error
    if trial_num == 1
        tmp_ml_err_dbf = squeeze(sim_res.ml_err_dbf);
        tmp_ml_err_dbf = tmp_ml_err_dbf(ii,:);
        sim_res.ml_err_dbf_mean(ii,:) = tmp_ml_err_dbf;
        sim_res.ml_err_dbf_cov(ii,:) = 0;
    elseif trial_num > 1
        tmp_ml_err_dbf = squeeze(sim_res.ml_err_dbf(ii,:,:));   
        sim_res.ml_err_dbf_mean(ii,:) = mean(tmp_ml_err_dbf,1);
        sim_res.ml_err_dbf_cov(ii,:) = diag(cov(tmp_ml_err_dbf))';
    end
        
    if trial_num == 1
        tmp_ml_err_cons = squeeze(sim_res.ml_err_cons);
        tmp_ml_err_cons = tmp_ml_err_cons(ii,:);
        sim_res.ml_err_cons_mean(ii,:) = tmp_ml_err_cons;
        sim_res.ml_err_cons_cov(ii,:) = 0;
    elseif trial_num > 1
        tmp_ml_err_cons = squeeze(sim_res.ml_err_cons(ii,:,:));     
        sim_res.ml_err_cons_mean(ii,:) = mean(tmp_ml_err_cons,1);
        sim_res.ml_err_cons_cov(ii,:) = diag(cov(tmp_ml_err_cons)');
    end
       
    % norm of cov of pdf
    if trial_num == 1
        tmp_pdf_norm_dbf = squeeze(sim_res.pdf_norm_dbf);
        tmp_pdf_norm_dbf = tmp_pdf_norm_dbf(ii,:);
        sim_res.pdf_norm_dbf_mean(ii,:) = tmp_pdf_norm_dbf;
        sim_res.pdf_norm_dbf_cov(ii,:) = 0;
    elseif trial_num > 1
        tmp_pdf_norm_dbf = squeeze(sim_res.pdf_norm_dbf(ii,:,:));
        sim_res.pdf_norm_dbf_mean(ii,:) = mean(tmp_pdf_norm_dbf,1);
        sim_res.pdf_norm_dbf_cov(ii,:) = diag(cov(tmp_pdf_norm_dbf)');
    end    
    
    if trial_num == 1
        tmp_pdf_norm_cons = squeeze(sim_res.pdf_norm_cons);
        tmp_pdf_norm_cons = tmp_pdf_norm_cons(ii,:);
        sim_res.pdf_norm_cons_mean(ii,:) = tmp_pdf_norm_cons;
        sim_res.pdf_norm_cons_cov(ii,:) = 0;
    elseif trial_num > 1
        tmp_pdf_norm_cons = squeeze(sim_res.pdf_norm_cons(ii,:,:));
        sim_res.pdf_norm_cons_mean(ii,:) = mean(tmp_pdf_norm_cons,1);
        sim_res.pdf_norm_cons_cov(ii,:) = diag(cov(tmp_pdf_norm_cons)');
    end
    
    % entropy of pdf
    if trial_num == 1
        tmp_entropy_dbf = squeeze(sim_res.entropy_dbf);
        tmp_entropy_dbf = tmp_entropy_dbf(ii,:);
        sim_res.entropy_dbf_mean(ii,:) = tmp_entropy_dbf;
        sim_res.entropy_dbf_cov(ii,:) = 0;
    elseif trial_num > 1
        tmp_entropy_dbf = squeeze(sim_res.entropy_dbf(ii,:,:));     
        sim_res.entropy_dbf_mean(ii,:) = mean(tmp_entropy_dbf,1);
        sim_res.entropy_dbf_cov(ii,:) = diag(cov(tmp_entropy_dbf)');
    end
    
    if trial_num == 1
        tmp_entropy_cons = squeeze(sim_res.entropy_cons);
        tmp_entropy_cons = tmp_entropy_cons(ii,:);
        sim_res.entropy_cons_mean(ii,:) = tmp_entropy_cons;
        sim_res.entropy_cons_cov(ii,:) = diag(cov(tmp_entropy_cons)');
    elseif trial_num > 1
        tmp_entropy_cons = squeeze(sim_res.entropy_cons(ii,:,:));  
        sim_res.entropy_cons_mean(ii,:) = mean(tmp_entropy_cons,1);
        sim_res.entropy_cons_cov(ii,:) = diag(cov(tmp_entropy_cons)');
    end    
end

% ml error
tmp_ml_err_cent = sim_res.ml_err_cent;
sim_res.ml_err_cent_mean = mean(tmp_ml_err_cent,1);
sim_res.ml_err_cent_cov = diag(cov(tmp_ml_err_cent)');

% norm of cov of pdf
tmp_pdf_norm_cent = sim_res.pdf_norm_cent;
sim_res.pdf_norm_cent_mean = mean(tmp_pdf_norm_cent,1);
sim_res.pdf_norm_cent_cov = diag(cov(tmp_pdf_norm_cent)');

% entropy of pdf
tmp_entropy_cent = sim_res.entropy_cent;
sim_res.entropy_cent_mean = mean(tmp_entropy_cent,1);
sim_res.entropy_cent_cov = diag(cov(tmp_entropy_cent)');

%% %%%%%%%%%%%%%% plot the performance metrics %%%%%%%%%%%%%%%%%
plot_rbt_idx = 1:2:5; % draw robot 1, 3, 5
% ml error
fig_cnt = fig_cnt+1;
hf_err = figure(fig_cnt);
line_clr = ['r','g','b','c','m','k'];
line_marker = {'o','*','s','d','^','h'};

% for LIFO-DBF, we draw different robot's performance metrics
for i=plot_rbt_idx
    plot(1:count-2,sim_res.ml_err_dbf_mean(i,1:count-2),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
    % errorbar(1:count-2,sim_res.ml_err_dbf_mean(i,1:count-2),sqrt(sim_res.ml_err_dbf_cov(i,1:count-2)),...
    %         line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
end

% for consensus, we draw one robot's performance metrics. theoretically,
% all robots' should be the same, however, my current way does not make
% this happen, which I have written in the note.docx. need to change this
% in the future.

% for i=1:NumOfRobot
%     plot(1:count-2,rbt_cons(i).ml_err_cons(1:count-2),line_clr(i),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
% end
plot(1:count-2,sim_res.ml_err_cons_mean(1,1:count-2),line_clr(2),'LineStyle','--','LineWidth',2,'Marker',line_marker{2},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.ml_err_cons_mean(1,1:count-2),sqrt(sim_res.ml_err_cons_cov(1,1:count-2)),...
%     line_clr(1),'LineStyle','--','LineWidth',2,'Marker',line_marker{1},'MarkerSize',2); hold on;

% only on centralized filter 
plot(1:count-2,sim_res.ml_err_cent_mean(1:count-2),line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{6},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.ml_err_cent_mean(1:count-2),sqrt(sim_res.ml_err_cent_cov(1:count-2)),...
%     line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{6},'MarkerSize',2); hold on;
xlim([0,count-1])

% add legend
[~, hobj1] = legend('DBF-R1','DBF-R3','DBF-R5','Consen','Central');
textobj = findobj(hobj1, 'type', 'text');
set(textobj, 'fontsize', 15);

title('Target Position Error','FontSize',30);
set(gca,'fontsize',30)
xlabel('Time','FontSize',30);
ylabel('Position Error','FontSize',30);

% pdf covariance norm
% results are hard to interpret. So just not include this figure
%{
fig_cnt = fig_cnt+1;
hf_cov = figure(fig_cnt);
line_clr = ['r','g','b','c','m','k'];
line_marker = {'o','*','s','d','^','h'};
for i=plot_rbt_idx
%     plot(1:count-2,rbt(i).pdf_norm_dbf(1:count-2),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
    plot(1:count-2,sim_res.pdf_norm_dbf_mean(i,1:count-2),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
%     errorbar(1:count-2,sim_res.pdf_norm_dbf_mean(i,1:count-2),sqrt(sim_res.pdf_norm_dbf_cov(i,1:count-2)),...
%         line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
end
[~, hobj2] = legend('Robot 1','Robot 2','Robot 3','Robot 4','Robot 5','Robot 6');
textobj = findobj(hobj2, 'type', 'text');
set(textobj, 'fontsize', 24);

% plot(1:count-2,rbt_cons(i).pdf_norm_cons(1:count-2),line_clr(i),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
plot(1:count-2,sim_res.pdf_norm_cons_mean(1,1:count-2),line_clr(2),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.pdf_norm_cons_mean(1,1:count-2),sqrt(sim_res.pdf_norm_cons_cov(1,1:count-2)),...
%     line_clr(1),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;

% plot(1:count-2,rbt_cent.pdf_norm_cent(1:count-2),line_clr(i),'LineStyle','-.','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
plot(1:count-2,sim_res.pdf_norm_cent_mean(1:count-2),line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.pdf_norm_cent_mean(1:count-2),sqrt(sim_res.pdf_norm_cent_cov(1:count-2)),...
%     line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
xlim([0,count-1])

title('Covariance of Target PDF','FontSize',30);
set(gca,'fontsize',30)
xlabel('Time','FontSize',30);
ylabel('Norm of Covariance Matrix','FontSize',30);
%}

% entropy
fig_cnt = fig_cnt+1;
hf_ent = figure(fig_cnt);
line_clr = ['r','g','b','c','m','k'];
line_marker = {'o','*','s','d','^','h'};
for i=plot_rbt_idx
    %     plot(1:count-2,rbt(i).entropy(1:count-2),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
    plot(1:count-2,sim_res.entropy_dbf_mean(i,1:count-2),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
    %     errorbar(1:count-2,sim_res.entropy_dbf_mean(i,1:count-2),sqrt(sim_res.entropy_dbf_cov(i,1:count-2)),line_clr(i),'LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
end

% plot(1:count-2,rbt_cons(i).entropy(1:count-2),line_clr(i),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
plot(1:count-2,sim_res.entropy_cons_mean(1,1:count-2),line_clr(2),'LineStyle','--','LineWidth',2,'Marker',line_marker{2},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.entropy_cons_mean(1,1:count-2),sqrt(sim_res.entropy_cons_cov(1,1:count-2)),line_clr(1),'LineStyle','--','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;

% plot(1:count-2,rbt_cent.entropy(1:count-2),line_clr(i),'LineStyle','-.','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
plot(1:count-2,sim_res.entropy_cent_mean(1:count-2),line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{6},'MarkerSize',2); hold on;
% errorbar(1:count-2,sim_res.entropy_cent_mean(1:count-2),sqrt(sim_res.entropy_cent_cov(1:count-2)),line_clr(6),'LineStyle','-.','LineWidth',2,'Marker',line_marker{i},'MarkerSize',2); hold on;
xlim([0,count-1])

% add legend
[~, hobj3] = legend('DBF-R1','DBF-R3','DBF-R5','Consen','Central');
textobj = findobj(hobj3, 'type', 'text');
set(textobj, 'fontsize', 15);

title('Entropy of the Target PDF','FontSize',30);
set(gca,'fontsize',30)
xlabel('Time','FontSize',30);
ylabel('Entropy','FontSize',30);

% save metrics plots
%{
switch Selection2
    case 1,  tag = 'sta_sen_sta_tar';
    case 2,  tag = 'sta_sen_mov_tar';
    case 3,  tag = 'mov_sen_sta_tar';
    case 4,  tag = 'mov_sen_mov_tar';
end
file_name2 = sprintf('./figures/data_exchange/%s_entropy_%s',tag,datestr(now,1));
if save_file == 1
    saveas(hf_ent,file_name2,'fig')
    saveas(hf_ent,file_name2,'jpg')
end
%}

%% save robot structure
switch Selection
    case 1,  tag = 'sta_sen_sta_tar';
    case 2,  tag = 'sta_sen_mov_tar';
    case 3,  tag = 'mov_sen_sta_tar';
    case 4,  tag = 'mov_sen_mov_tar';
end

if save_file == 1
    file_name = sprintf('./figures/data_exchange_switch/ACC16/%s_robot_%s.mat',tag,datestr(now,1));
    save(file_name,'sim','fld') % save these variables to recover the performance metrics when necessary
%     save(file_name) % save current workspace
end