# The complete ssdr function, consisting of discovering the tunining parameter candidates.
ssdr_func <- function(x_train, y_train, x_val, y_val, H=5, categorical=FALSE, type = 'sir', lambda.factor=0.5, nlam_msda=10,
                      lam1_fac=seq(1.2,0.01, length.out = 10), lam2_fac=seq(0.001,0.2, length.out = 10),
                      gamma=c(10,30,50), cut_y=TRUE, plot = TRUE, ...){
  
  #### The start of our methods
  
  ################################################
  # MSDA
  ################################################
  if(categorical == FALSE){
    ybreaks <- as.numeric(quantile(y_train, probs=seq(0,1, by=1/H), na.rm=TRUE))
    yclass <- cut(y_train, breaks = ybreaks, include.lowest = TRUE, labels = FALSE)
    nclass <- as.integer(length(unique(yclass)))
  }else if(categorical == TRUE){
    nclass <- H <- length(unique(y_train))
    yclass <- y_train
  }
  
  fit_1 <- my_msda(x_train, y_train, yclass = yclass, H=H, type = type, nlambda=nlam_msda, maxit=1e3, lambda.factor=lambda.factor, cut_y=cut_y)
  
  sigma0 <- as.matrix(fit_1$sigma)
  mu0 <- as.matrix(fit_1$mu)
  lam_msda <- fit_1$lambda
  Beta_msda <- fit_1$theta
  rank_msda <- fit_1$rank

  # Cut matrix
  Beta_msda <- cut_mat(Beta_msda, 1e-3, rank_msda)
  
  # validation
  eval_msda <- eval_val_dc(Beta_msda, x_val, y_val)
  
  # The optimal lambda1
  id_min_msda <- which.min(eval_msda)
  lam1_min_msda <- lam_msda[id_min_msda]
  
  if(plot){
    plot(1:length(eval_msda), eval_msda, xlab = "", ylab = "Error (MSDA)")
    points(id_min_msda, eval_msda[id_min_msda], col = 'red')
  }
  
  # calculate C, IC, Frobenious distance, rank and subspace distance
  B_msda <- as.matrix(Beta_msda[[id_min_msda]])
  
  
  ################################################
  # SSDR
  ################################################
  
  # Lambda1 candidates
  lam1 <- (lam1_min_msda)*lam1_fac
  n1 <- length(lam1)
  
  # Gamma candidates
  gamma <- gamma
  n3 <- length(gamma)
  
  # Lambda2 candidates
  d <- svd(B_msda)$d
  lam2 <- d[1] * matrix(gamma, ncol = 1) %*% matrix(lam2_fac, nrow = 1)
  n2 <- dim(lam2)[2]
  
  # if lam2 just contains one single value 0, then msda matrix is zero matrix
  if (all(lam2 == 0)){
    
    print("All lambda2 are zero, msda matrix is zero matrix\n")
    results <- c(NA, NA, NA, NA, NA, NA, NA, NA, NA, NA)
    results <- as.data.frame(t(results))
    colnames(results) <- c("r_ssdr", "lam1_min_msda","id_msda", "lam1_min_ssdr", "lam2_min_ssdr", "gam_min_ssdr", "id1", "id2", "id_gam", "step")
    
    return(list(mat = NULL, results = results, eval = NA, svB = NULL, svC = NULL))
    
  }else{
    
    # fit with ssdr
    nobs <- as.integer(dim(x_train)[1])
    nvars <- as.integer(dim(x_train)[2])
    
    fit_2 <- ssdr(sigma0, mu0, nobs, nvars, lam1, lam2, gamma, ...)
    
    Beta_ssdr <- fit_2$Beta
    
    # In some cases, all the Beta is null because the Fortran code didn't return a converaged B matrix 
    if (all(sapply(Beta_ssdr, is.null))) {
      print("No converged matrix returned")
      results <- c(NA,NA, NA, NA, NA, NA, NA, NA, NA, NA)
      results <- as.data.frame(t(results))
      colnames(results) <- c("r_ssdr", "lam1_min_msda","id_msda", "lam1_min_ssdr", "lam2_min_ssdr", "gam_min_ssdr", "id1", "id2", "id_gam", "step")
      
      return(list(mat = NULL, results = results, eval = NA, svB = NULL, svC = NULL))
    }
    
    gamma_list <- fit_2$gamma
    lam1_list <- fit_2$lam1
    lam2_list <- fit_2$lam2
    rank_ssdr <- fit_2$rank
    step <- fit_2$step
    time_ssdr <- fit_2$time

    # validate
    eval_ssdr <- eval_val_dc(Beta_ssdr, x_val, y_val)
    
    if(plot){
      ind <- which(sapply(Beta_ssdr, is.null))
      rank_ssdr_C[ind] <- 0
      eval_ssdr[ind] <- max(eval_ssdr, na.rm = TRUE)
      plot(1:length(eval_ssdr), eval_ssdr)
      points(which(rank_ssdr_C > 2), eval_ssdr[rank_ssdr_C > 2], col = 'green')
      points(which(rank_ssdr_C == 2), eval_ssdr[rank_ssdr_C == 2], col = 'red')
      points(which(rank_ssdr_C == 1), eval_ssdr[rank_ssdr_C == 1], col = 'blue')
      points(ind, eval_ssdr[ind], pch=4)
  
      for(i in 1:(n1-1)){
        abline(v = n2*n3*i+1, lty = 'dashed')
      }
    }
    
    # The optimal lambda1 and lambda2 
    id_min_ssdr <- which.min(eval_ssdr)
    lam1_min_ssdr <- lam1_list[[id_min_ssdr]]
    lam2_min_ssdr <- lam2_list[[id_min_ssdr]]
    gamma_min_ssdr <- gamma_list[[id_min_ssdr]]
    id_lam1 <- which(lam1_min_ssdr == lam1)
    id_lam2 <- which(lam2_min_ssdr == lam2, arr.ind = TRUE)[2]
    id_gamma <- which(gamma_min_ssdr == gamma)
    
    # The optimal ssdr
    B_ssdr <- Beta_ssdr[[id_min_ssdr]]
    
    if(is.null(B_ssdr)){
      print("Optimal matrix is a null matrix")
      
      results <- c(NA, lam1_min_msda, id_min_msda, lam1_min_ssdr, lam2_min_ssdr, gamma_min_ssdr, id_lam1, id_lam2, id_gamma, mean(unlist(step)))
      results <- as.data.frame(t(results))
      colnames(results) <- c("r_ssdr", "lam1_min_msda","id_msda", "lam1_min_ssdr", "lam2_min_ssdr", "gam_min_ssdr", "id1", "id2", "id_gam", "step")

      return(list(mat = NULL, results = results, eval = eval_ssdr, svB = NULL, svC = NULL))
      
    }else{
      # Calculate C, IC, Frobinious distance, subspace distance
      r_ssdr <- rank_ssdr[[id_min_ssdr]]
      
      # save the singular values of each optimal matrix B and C
      # svB <- sv_list_B[[id_min_ssdr]]
      # svC <- sv_list_C[[id_min_ssdr]]
      
      id <- data.frame(id_msda = id_min_msda, id_lam1=id_lam1, id_lam2 = id_lam2, id_gamma = id_gamma)
      
      return(list(Beta = B_ssdr, rank = r_ssdr, eval = eval_ssdr, id = id, lam1 = lam1, lam2 = lam2, gamma = gamma,
                  lam1_msda.min = lam1_min_msda, lam1.min = lam1_min_ssdr, lam2.min = lam2_min_ssdr, gamma.min = gamma_min_ssdr, 
                  step_ssdr = mean(unlist(step)) ))
    }
    
  }
}



ssdr.cv <- function(x, y, H=5, categorical=FALSE, type = 'sir', lambda.factor=0.5, nlam_msda=10, 
                    lam1_fac=seq(1.2,0.01, length.out = 10), lam2_fac=seq(0.001,0.2, length.out = 10),
                    gamma=c(10,30,50), cut_y=TRUE, nfolds = 5, plot = FALSE, ...){
  
  # col.names <- colnames(x)
  x <- as.matrix(x)
  y <- drop(y)
  order_y <- order(y)
  x <- x[order_y,,drop=FALSE]
  y <- y[order_y]
  
  nobs <- as.integer(dim(x)[1])
  nvars <- as.integer(dim(x)[2])
  # Cross validation with msda to find lambda1_msda
  fit_1 <- msda.cv(x, y, H=H, categorical=categorical, type=type, nlam=nlam_msda, lambda.factor=lambda.factor, cut_y=cut_y, 
                   nfolds=nfolds, maxit=1e3, plot = plot)
  id_min_msda <- fit_1$id
  lam1_min_msda <- fit_1$lambda
  B_msda <- as.matrix(fit_1$Beta)
  sigma0 <- as.matrix(fit_1$sigma)
  mu0 <- as.matrix(fit_1$mu)
  
  # Generate tuning parameter candidates
  lam1 <- (lam1_min_msda)*lam1_fac
  n1 <- length(lam1)
  
  gamma <- gamma
  n3 <- length(gamma)
  
  d <- svd(B_msda)$d
  lam2 <- d[1] * matrix(gamma, ncol = 1) %*% matrix(lam2_fac, nrow = 1)
  n2 <- dim(lam2)[2]
  
  # if lam2 just contains one single value 0, then ssdr just degenerated to msda
  if (all(lam2 == 0)){
    print("All lambda2 are zero, msda matrix is zero matrix\n")
    return(list(Beta = NULL, rank = NA, cvm = NA, cvsd = NA, id = NA, lam1 = lam1, lam2 = lam2, gamma = gamma,
                lam1_msda.min = lam1_min_msda, lam1.min = NA, lam2.min = NA, gamma.min = NA))
  }else{
    # Cross-validation
    if (nfolds < 3) stop("nfolds must be larger than 3")
    if (nfolds > nobs) stop("nfolds is larger than the sample size")
    
    if(categorical == FALSE){
       ybreaks <- as.numeric(quantile(y, probs=seq(0,1, by=1/H), na.rm=TRUE))
       yclass <- cut(y, breaks = ybreaks, include.lowest = TRUE, labels = FALSE)
       nclass <- as.integer(length(unique(yclass)))
    }else if(categorical == TRUE){
      nclass <- H <- length(unique(y))
      yclass <- y
    }

    count <- as.numeric(table(yclass))
    fold <- c()
    for(cnt in count){
      fold <- c(fold, sample(rep(seq(nfolds), length = cnt)))
    }

    eval_all <- sapply(1:nfolds, function(k){
      x_train <- x[fold!=k,,drop=FALSE]
      x_val <- x[fold==k,,drop=FALSE]
      y_train <- y[fold!=k]
      y_val <- y[fold==k]
      yclass_fold <- yclass[fold!=k]
      
      prep_fold <- prep(x_train, y_train, yclass=yclass_fold, H=H, type = type, cut_y=cut_y)
      nobs_fold <- as.integer(dim(x_train)[1])
      nvars_fold <- as.integer(dim(x_train)[2])
      sigma_fold <- prep_fold$sigma
      mu_fold <- prep_fold$mu
      
      fit_fold <- ssdr(sigma_fold, mu_fold, nobs_fold, nvars_fold, lam1, lam2, gamma, ...)
      Beta_fold <- fit_fold$Beta
      
      if (all(sapply(Beta_fold, is.null))) {
        print(paste0("Fold ",1,": No converged matrix returned"))
        return(rep(NA, length(Beta_fold)))
      }
      
      rank_fold <- fit_fold$rank
      # evaluate
      eval_fold <- eval_val_dc(Beta_fold, x_val, y_val)
      
      if (plot){
        ind <- which(sapply(Beta_fold, is.null))
        rank_fold_copy <- rank_fold
        eval_copy <- eval_fold
        rank_fold_copy[ind] <- 999
        eval_copy[ind] <- max(eval_copy, na.rm = TRUE)
        plot(1:length(eval_copy), eval_copy, xlab = "", ylab = "Error (SSDR)", type = 'n', main = paste("Fold", k))
        points(which((2 < rank_fold_copy) & (rank_fold_copy < 999)), eval_copy[(2 < rank_fold_copy) & (rank_fold_copy < 999)], col = 'green')
        points(which(rank_fold_copy == 2), eval_copy[rank_fold_copy == 2], col = 'red')
        points(which(rank_fold_copy == 1), eval_copy[rank_fold_copy == 1], col = 'blue')
        points(which(rank_fold_copy == 0), eval_copy[rank_fold_copy == 0], col = 'black')
        points(ind, eval_copy[ind], pch=4)
        for(i in 1:(n1-1)){
          abline(v = n2*n3*i+1, lty = 'dashed')
        }
      }
      eval_fold
    })
    
    if(is.vector(eval_all)){
      eval_all <- t(as.matrix(eval_all))
    }
    
    # If no matrix is converged in any fold, return NULL matrix
    if(all(is.na(eval_all))){
      print("No converged matrix returned in the process of cross-validation\n")
      return(list(Beta = NULL, rank = NA, cvm = NA, cvsd = NA, id = NA, lam1 = lam1, lam2 = lam2, gamma = gamma,
                  lam1_msda.min = lam1_min_msda, lam1.min = NA, lam2.min = NA, gamma.min = NA))
    }
    
    cvm <- apply(eval_all, 1, mean, na.rm=TRUE)
    cvsd <- sqrt(colMeans(scale(t(eval_all), cvm, FALSE)^2, na.rm = TRUE)/(nfolds-1))
    
    # Refit with the optimal parameters
    cvm_tmp <- cvm
    for(i_tmp in 1:length(cvm_tmp)){
      id_min_ssdr <- which.min(cvm_tmp)
      id_lam1 <- ceiling(id_min_ssdr/(n2*n3))
      id_gamma <- ceiling((id_min_ssdr-(id_lam1-1)*(n2*n3))/n2)
      id_lam2 <- id_min_ssdr-(id_lam1-1)*(n2*n3)-(id_gamma-1)*n2
      lam1_min_ssdr <- lam1[id_lam1]
      gamma_min_ssdr <- gamma[id_gamma]
      lam2_min_ssdr <- lam2[id_gamma,id_lam2]
      fit_full <- ssdr(sigma0, mu0, nobs, nvars, lam1_min_ssdr, matrix(lam2_min_ssdr,1,1), gamma_min_ssdr, ...)
      B_ssdr <- fit_full$Beta[[1]]
      r_ssdr <- fit_full$rank[[1]]
      if(!is.null(B_ssdr)){
        break
      }else{
        cvm_tmp[id_min_ssdr] <- NA
      }
    }
    
    id <- data.frame(id_msda = id_min_msda, id_lam1 = id_lam1, id_lam2 = id_lam2, id_gamma = id_gamma)
    
    if(is.null(B_ssdr)){
      print("Optimal matrix is a null matrix\n")
      return(list(Beta = NULL, rank = NA, cvm = cvm, cvsd = cvsd, id = id, lam1 = lam1, lam2 = lam2, gamma = gamma,
                  lam1_msda.min = lam1_min_msda, lam1.min = lam1_min_ssdr, lam2.min = lam2_min_ssdr, gamma.min = gamma_min_ssdr))
    }else{
      return(list(Beta = B_ssdr, rank = r_ssdr, cvm = cvm, cvsd = cvsd, id = id, lam1 = lam1, lam2 = lam2, gamma = gamma,
                  lam1_msda.min = lam1_min_msda, lam1.min = lam1_min_ssdr, lam2.min = lam2_min_ssdr, gamma.min = gamma_min_ssdr))
    }
  }
}


msda.cv <- function(x, y, H=5, categorical=FALSE, type='sir', nlam=10, lambda.factor=0.5, cut_y=FALSE, nfolds=5, maxit=1e3, plot=TRUE){
  
  if(categorical == FALSE){
    ybreaks <- as.numeric(quantile(y, probs=seq(0,1, by=1/H), na.rm=TRUE))
    yclass <- cut(y, breaks = ybreaks, include.lowest = TRUE, labels = FALSE)
    nclass <- as.integer(length(unique(yclass)))
  }else if(categorical == TRUE){
    nclass <- H <- length(unique(y))
    yclass <- y
  }
  
  # Fit full data, obtain the msda lambda candidates
  fit <- my_msda(x, y, yclass = yclass, H = H, nlambda=nlam, type = type, lambda.factor=lambda.factor, maxit=maxit, cut_y=cut_y)
  lam_msda <- fit$lambda
  if(!is.numeric(lam_msda)){
    stop('No lambda from MSDA!')
  }
  Beta_msda <- fit$theta
  sigma0 <- as.matrix(fit$sigma)
  mu0 <- as.matrix(fit$mu)
  rank_msda <- fit$rank
  Beta_msda <- cut_mat(Beta_msda, 1e-3, rank_msda)
  
  # Cross-validation
  count <- as.numeric(table(yclass))
  fold <- c()
  for(cnt in count){
    fold <- c(fold, sample(rep(seq(nfolds), length = cnt)))
  }

  eval_all <- sapply(1:nfolds, function(k){
    x_train <- x[fold!=k,,drop=FALSE]		
    x_val <- x[fold==k,,drop=FALSE]		
    y_train <- y[fold!=k]
    y_val <- y[fold==k]
    yclass_fold <- yclass[fold!=k]
      
    # matrix is already cut inside msda_func
    fit_fold <- my_msda(x_train, y_train, yclass = yclass_fold, H=H, nlambda=nlam, type=type, lambda.factor=lambda.factor, lambda=lam_msda, maxit=maxit, cut_y=cut_y)
    Beta_fold <- fit_fold$theta
    rank_fold <- fit_fold$rank
    Beta_fold <- cut_mat(Beta_fold, 1e-3, rank_fold)
    
    # return evaluation of each fold
    eval_fold <- eval_val_dc(Beta_fold, x_val, y_val)
    if(length(eval_fold) != length(lam_msda)){
      eval_fold <- c(eval_fold, rep(NA, length(lam_msda) - length(eval_fold)))
    }
    eval_fold
  })
  
  if(is.vector(eval_all)){
   eval_all <- t(as.matrix(eval_all))
  }
  
  if(all(is.na(eval_all))){
    stop("No valid cross-validation error (msda doesn't converge for all lambdas)")
  }
  
  cvm <- apply(eval_all, 1, mean, na.rm=TRUE)
  
  # The optimal lambda1
  id_min <- which.min(cvm)
  lam1_min <- lam_msda[id_min]
  B_msda <- as.matrix(Beta_msda[[id_min]])
  
  # Recalculate the rank
  rank_min <- rank_func(B_msda, thrd = 1e-3)
  
  if(plot){
    plot(1:length(cvm), cvm, xlab = "", ylab = "CV error (MSDA)")
    points(id_min, cvm[id_min], col = 'red')
  }
  
  list(id = id_min, lambda = lam1_min, Beta = B_msda, sigma = sigma0, mu = mu0, rank = rank_min)
}

# calculate the Beta and the lambda sequences using msda function
my_msda <- function(x, y, yclass=NULL, H=5, nlambda=100, type='sir', lambda.factor=ifelse((nobs - nclass)<=nvars, 0.2, 1e-03),
                    lambda=NULL, dfmax=nobs, pmax=min(dfmax*2 + 20, nvars), pf=rep(1, nvars), eps=1e-04, maxit=1e+06,
                    sml=1e-06, verbose=FALSE, perturb=NULL, cut_y=FALSE) {
  
  this.call <- match.call()
  nobs <- as.integer(dim(x)[1])
  nvars <- as.integer(dim(x)[2])
  vnames <- colnames(x)
  
  # Get sigma and mu from prep function
  prep_out <- prep(x, y, yclass = yclass, H=H, type=type, cut_y=cut_y)
  sigma <- prep_out$sigma
  mu <- prep_out$mu
  nclass <- prep_out$nclass
  prior <- prep_out$prior
  
  ######################################
  if (!is.null(perturb)) 
    diag(sigma) <- diag(sigma) + perturb
  if (is.null(vnames)) 
    vnames <- paste("V", seq(nvars), sep = "")
  nk <- as.integer(dim(mu)[2])
  ## parameter setup
  if (length(pf) != nvars) 
    stop("The size of penalty factor must be same as the number of input variables")
  maxit <- as.integer(maxit)
  verbose <- as.integer(verbose)
  sml <- as.double(sml)
  pf <- as.double(pf)
  eps <- as.double(eps)
  dfmax <- as.integer(dfmax)
  pmax <- as.integer(pmax)
  ## lambda setup
  nlam <- as.integer(nlambda)
  if (is.null(lambda)) {
    if (lambda.factor >= 1)
      stop("lambda.factor should be less than 1")
    flmin <- as.double(lambda.factor)
    ulam <- double(1)  #ulam=0 if lambda is missing
  } else {
    # flmin=1 if user define lambda
    flmin <- as.double(1)
    if (any(lambda < 0))
      stop("lambdas should be non-negative")
    ulam <- as.double(rev(sort(lambda)))  #lambda is declining
    nlam <- as.integer(length(lambda))
  }
  ## call Fortran core
  fit <- .Fortran("msda", obj = double(nlam), nk, nvars, as.double(sigma), as.double(t(mu)), 
                  pf, dfmax, pmax, nlam, flmin, ulam, eps, maxit, sml, verbose, nalam = integer(1), 
                  theta = double(pmax * nk * nlam), itheta = integer(pmax), ntheta = integer(nlam), 
                  alam = double(nlam), npass = integer(1), jerr = integer(1))
  
  ## output
  outlist <- formatoutput(fit, maxit, pmax, nvars, vnames, nk)
  
  rank <- vector("list", length(outlist$theta))
  for (i in 1:length(outlist$theta)){
    if(!is.null(outlist$theta[[i]])){
      rank[[i]] <- rank_func(outlist$theta[[i]], thrd = 1e-3)
    }
  }
  
  outlist <- c(outlist, 
               list(x = x, y = y, npasses = fit$npass, jerr = fit$jerr, sigma = sigma, mu = mu, call = this.call, rank = rank,
                    prior = ifelse(type %in% c('sir','save'), prior, NA)) )
  if (is.null(lambda)) 
    outlist$lambda <- lamfix(outlist$lambda)
  class(outlist) <- c("msda")
  outlist
}

# ssdr algorithm function
ssdr <- function(sigma, mu, nobs, nvars, lam1, lam2, gam, pf=rep(1, nvars), dfmax=nobs, pmax=min(dfmax * 2 + 20, nvars), 
                 eps=1e-04, maxit=1e+06, sml=1e-06, verbose = FALSE, maxit_outer=1e+3, eps_outer=1e-3){
  
  flmin <- as.double(1)
  nlam <- as.integer(1)
  vnames <- as.character(1:nvars)
  nk <- as.integer(dim(mu)[2])
  pf <- as.double(pf)
  dfmax <- as.integer(dfmax)
  pmax <- as.integer(pmax)
  eps <- as.double(eps)
  maxit <- as.integer(maxit)
  sml <- as.double(sml)
  verbose <- as.integer(verbose)
  maxit_outer <- as.integer(maxit_outer)
  eps_outer <- as.double(eps_outer)
  
  sigma0 <- sigma
  mu0 <- mu
  n1 <- length(lam1)
  n2 <- ncol(lam2)
  n3 <- length(gam)
  nparams <- n1*n2*n3
  
  mat <- vector("list", nparams)
  step_final <- vector("list", nparams)     # To store the iteration times of each run
  time_final <- vector("list", nparams)     # To store the running time of each run
  lam1_list <- vector("list", nparams)
  lam2_list <- vector("list", nparams)
  gamma_list <- vector("list", nparams)
  rank_list <- vector("list", nparams)
  
  sv_list_B <- vector("list", nparams)
  sv_list_C <- vector("list", nparams)
  
  # The number of converged matrices
  nlam_ssdr <- 0
  
  for(i in 1:n1){
    ulam <- as.double(lam1[i])
    
    for(j in 1:n3){
      gamma <- gam[j]
      
      for(k in 1:n2){
        
        lambda2 <- lam2[j,k]
        
        # Maximal interation for outer loop
        sigma <- sigma0 + gamma*diag(rep(1,ncol(sigma0)), ncol(sigma0),ncol(sigma0))
        ##################################
        # SSDR
        ##################################
        # Initialize three matrices
        Bold <- matrix(0,dim(mu0)[1], dim(mu0)[2])
        Cold <- matrix(0,dim(mu0)[1], dim(mu0)[2])
        etaold <- matrix(0,dim(mu0)[1], dim(mu0)[2])
        
        # The MAIN loop of SSDR method
        step_ssdr <- 0    
        
        start_time <- Sys.time()
        
        repeat{
          
          step_ssdr <- step_ssdr + 1
          
          # Update B
          mu <- t(mu0 - etaold + gamma * Cold)
          fit <- .Fortran("msda", obj = double(nlam), nk, nvars, as.double(sigma), 
                          as.double(mu), pf, dfmax, pmax, nlam, flmin, ulam, 
                          eps, maxit, sml, verbose, nalam = integer(1), theta = double(pmax * nk * nlam),
                          itheta = integer(pmax), ntheta = integer(nlam), 
                          alam = double(nlam), npass = integer(1), jerr = integer(1))
          
          # If jerr != 0, msda function returns abnormal results
          if (fit$jerr != 0){
            jerr <- fit$jerr
            break
          }
          
          outlist <- formatoutput(fit, maxit, pmax, nvars, vnames, nk)
          Bnew <- as.matrix(outlist$theta[[1]])
          
          # Update C
          Btemp <- Bnew + 1/gamma * etaold
          r <- svd(Btemp)
          U <- r$u
          V <- r$v
          D <- r$d
          lamtemp <- sapply(D, FUN = function(x) {max(0, x-lambda2/gamma)})
          Cnew <- U %*% diag(lamtemp, nrow = length(lamtemp), ncol = length(lamtemp)) %*% t(V)
          
          # Update mu
          etanew <- etaold + gamma * (Bnew - Cnew)
          
          # Exit condition
          # the success code is 1
          if(max(abs(Bnew - Bold)) < eps_outer){
            jerr <- 1
            break
          }
          # If jerr == 404, then maximal iteration is reached, we leave the matrix as null
          if(step_ssdr > maxit_outer){
            jerr <- 404
            print('Maximal iteration is reached.')
            break
          }
          
          Bold <- Bnew
          Cold <- Cnew
          etaold <- etanew
          
        }# End of repeat 
        end_time <- Sys.time()  # The time for each repeat
        
        # print(jerr)
        
        # If we get non-sparse matrix for msda, stop here, and leave the rest of matrices, svB, svC, etc. as NULL
        if(jerr < -10000){
          warning(paste0('The ',i, 'th lam1 is too small, no execution for the rest parameters lam2 and gamma.'))
          break
        }
        # If jerr == 1, then procedure converges, we save the matrix and sv.
        if(jerr==1){
          
          index <- (i-1)*n2*n3 + (j-1)*n2 + k
          nlam_ssdr <- nlam_ssdr + 1
          step_final[[index]] <- step_ssdr
          time_final[[index]] <- difftime(end_time, start_time, units = "secs")
          
          rank <- rank_func(Cnew, thrd = 1e-3)
          rank_list[[index]] <- rank
          
          # save the singular values of each candidates matrix B and C
          sv_list_B[[index]] <- svd(Bnew)$d
          sv_list_C[[index]] <- svd(Cnew)$d
          
          # Cut and select the left singular vector of Bnew
          if(rank == 0){
            Bnew <- matrix(0, nrow(Bnew), ncol(Bnew))
          }else{
            tmp <- svd(Bnew)$u[,1:rank, drop = FALSE]
            vec <- as.vector(tmp)
            vec[abs(vec) < 1e-3] <- 0
            Bnew <- matrix(vec, nrow(tmp), ncol(tmp))
          }
          
          mat[[index]] <- Bnew
          
          
          lam1_list[[index]] <- ulam
          gamma_list[[index]] <- gamma
          lam2_list[[index]] <- lambda2
        }
        
      }# End of lambda2
      
      if(jerr < -10000) break
      
    }# End of gam
    
  }# End of lambda1
  
  return(list(Beta = mat, rank = rank_list, step = step_final, time = time_final, nlam = nlam_ssdr, lam1 = lam1_list, lam2 = lam2_list, gamma = gamma_list, sv_list_B = sv_list_B, sv_list_C = sv_list_C))
  
}