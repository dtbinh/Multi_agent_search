mode_num = 1;

u_set = [zeros(2,1),ones(2,1),-ones(2,1)]; %inPara.u_set; 
V_set = {0.0001*eye(2),0.01*eye(2),0.01*eye(2)}; % 

fld_size = [100;100];

% [ptx,pty] = meshgrid(1:fld_size(1),1:fld_size(2));
% pt = [ptx(:),pty(:)];
% upd_matrix = cell(mode_num,1); % pred matrix for all motion models
% 
% for mode_cnt = 1:mode_num
%     % tmp_matrix(ii,:) is the transition probability P(x^i_k+1|x^j_k) for
%     % all x^j_k in the grid
%     tmp_matrix = zeros(size(pt,1),size(pt,1));
%     for ii = 1:size(pt,1)
%         display(ii)
%         % transition matrix
%         % tmp_trans(x,y) shows the transition probability P(x^i_k+1|[x;y]),
%         % considering the dynamic model of vehicle
%         tmp_trans = zeros(fld_size(1),fld_size(2));
% %         mu = pt(ii,:)'+u_set(:,ii);
%         for x = 1:fld_size(1)
%             for y = 1:fld_size(2)
%                 mu = [x;y]+u_set(:,mode_cnt);
%                 tmp_trans(x,y) = mvncdf([pt(ii,1)-0.5;pt(ii,2)-0.5],[pt(ii,1)+0.5;pt(ii,2)+0.5],mu,V_set{mode_cnt});
%             end
%         end
%         tmp_matrix(ii,:) = tmp_trans(:);
%     end
%     upd_matrix{mode_cnt} = tmp_matrix;
% end
% 
% save('upd_matrix2.mat','upd_matrix')


% [ptx1,pty1] = meshgrid(1:fld_size(1)-1,1:fld_size(2)-1);

% pt1 = [ptx1(:),pty1(:)];

% [ptx2,pty2] = meshgrid(2:fld_size(1),2:fld_size(2));

% pt2 = [ptx2(:),pty12(:)];

[ptx,pty] = meshgrid(0.5:1:fld_size(1)+0.5,0.5:1:fld_size(2)+0.5);
pt = [ptx(:),pty(:)];
upd_matrix = cell(mode_num,1); % pred matrix for all motion models
for mode_cnt = 1%:mode_num
    % tmp_matrix(ii,:) is the transition probability P(x^i_k+1|x^j_k) for    
    % all x^j_k in the grid    
    trans_mat = zeros(fld_size(1)*fld_size(2));
    count = 1;    
    for x = 1:fld_size(1)        
        for y = 1:fld_size(2)        
            display([x;y])
            mu = [x;y]+u_set(:,mode_cnt);
            % transition matrix            
            % tmp_trans(x,y) shows the transition probability P(x^i_k+1|[x;y]),            
            % considering the dynamic model of vehicle            
            % tmp_trans = zeros(fld_size(1),fld_size(2));            
            tmp_trans = mvncdf([ptx(:),pty(:)],mu',V_set{mode_cnt});
            tmp_trans_mat = (reshape(tmp_trans,fld_size(2)+1,fld_size(1)+1))';
            tmp_trans_mat2 = tmp_trans_mat(2:end,2:end)-tmp_trans_mat(1:end-1,2:end)-tmp_trans_mat(2:end,1:end-1)+tmp_trans_mat(1:end-1,1:end-1);
            tmp_trans_mat2 = tmp_trans_mat2';
            trans_mat(:,count) = tmp_trans_mat2(:);
            count = count + 1;                        
        end        
    end
    upd_matrix{mode_cnt} = trans_mat;
end